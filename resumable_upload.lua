#! /usr/bin/env lua

local socket = require("socket")
local io = require("io")

local host = '192.168.1.110'
local port = 80

local path = './'
local file_name = 'test.doc'
local block_max_size = 2^16
local remote_path = '/root/upload/'

local HTTP_URI = '/upload'
local HTTP_HOST = 'Host: '
local HTTP_CONTENT_LENGTH = 'Content-Length: '
local HTTP_CONTENT_TYPE = 'Content-Type: '
local HTTP_CONTENT_DISPOSITION = 'Content-Disposition: '
local HTTP_CONTENT_RANGE = 'X-Content-Range: '
local HTTP_SESSION_ID = 'Session-ID: '

function file_size(file)
    local current = file:seek('cur')
    local size = file:seek('end')
    file:seek('set', current)
    return size
end

function file_offset(file)
    local current = file:seek('cur')
    return current
end

function http_header_set_url(method, uri)
    if type(method) ~= 'string'
        or type(uri) ~= 'string' then
        assert(0)
    end

    return method .. ' ' .. uri .. ' ' .. 'HTTP/1.1\r\n'
end

function http_header_add_field(headers, key, val)
    if type(headers) ~= 'string'
        or type(headers) ~= 'string'
        or type(headers) ~= 'string' then
        assert(0)
    end

    return headers .. key .. ' ' .. val .. '\r\n'
end

function http_header_set_end(headers)
    return headers .. '\r\n'
end

function http_request(client, header, body)
    local err, err_msg

    err, err_msg = client:send(header)
    if err == nil then
        if string.match(err_msg, 'closed') then
            print('error socket closed by server.')
            return nil
        end
    end

    err, err_msg = client:send(body)
    if err == nil then
        if string.match(err_msg, 'closed') then
            print('error socket closed by server.')
            return nil
        end
    end

    return nil
end

function http_response(client)
    local header_table = {}
    local body
    local body_size
    local buffer_line
    local err_msg

    header_table = http_response_receive_header(client)
    if header_table ~= nil then
        for k, v in pairs(header_table) do
            print('info ' .. k..': '..v)
        end
    end

    body_size = header_table['Content-Length']
    if body_size == nil then
        if header_table['Transfer-Encoding'] == 'chunked' then
            buffer_line, err_msg = client:receive('*l')
            body_size = tonumber(string.gsub(buffer_line, ";.*", ""), 16)
        end
    end

    body = http_response_receive_body(client, body_size)
    print('info response body:', body)

    return header_table, body
end

function http_response_receive_header(client)
    local header = ''
    local header_table = {}
    local buffer_line
    local key, value
    local status_code

    buffer_line = client:receive('*l')
    if buffer_line == nil then
        print('error receive http response status line error.')
        return nil
    end
    --print('info ' .. buffer_line)

    status_code = http_response_parse_status_line(buffer_line)
    if status_line ~= nil then
        header_table['status_code'] = status_code
    end

    while true do
        buffer_line = client:receive('*l')
        if buffer_line == nil then
            print('error receive http response headers error.')
            break
        end
        --print('info ' .. buffer_line)

        header = header .. buffer_line

        --[[
            when reading http response end, buffer_line = ''
        --]]
        if buffer_line == '' then
            print('info recevie http response headers end.')
            break
        end

        key, value = http_response_parse_header_line(buffer_line)
        if key ~= nil then
            header_table[key] = value
        end
    end

    return header_table
end

function http_response_receive_body(client, size)
    local block

    block = client:receive(size)
    return block
end

function http_response_parse_status_line(status_line)
    local pattern = 'HTTP%/1%.1% %d*% '

    status_line = string.match(status_line, pattern)
    if status_line == nil then
        return nil
    end

    status = string.sub(status_line, 10, 12)
    status = tonumber(status)
    return status
end

function http_response_parse_header_line(line)
    local key, value

    if type(line) ~= 'string' then
        return nil
    end

    key, value = string.match(line, '^(.-):%s*(.*)')
    if not (key and value) then
        return nil
    end

    return key, value
end

client = socket.tcp()
client:connect(host, port)

file = io.open(path .. file_name, 'r')
assert(file ~= nil)

local block
local block_size
local file_size_all = file_size(file)
local cur_left = file_size_all
local last_left = file_size_all
local http_headers
local session_id = math.random(1000000)
while true do

    block = file:read(block_max_size)
    if block == nil then
        break
    end

    cur_left = file_size_all - file_offset(file)
    block_size = last_left - cur_left
    last_left = cur_left

    local req_header, req_body
    req_header = http_header_set_url('POST', HTTP_URI)
    req_header = http_header_add_field(req_header, HTTP_HOST, host)
    req_header = http_header_add_field(req_header, HTTP_CONTENT_LENGTH, tostring(block_size))
    req_header = http_header_add_field(req_header, HTTP_CONTENT_TYPE, 'application/octet-stream')
    req_header = http_header_add_field(req_header, HTTP_CONTENT_DISPOSITION, 'attachment;'..' file='..file_name..';'..' path=' .. remote_path)
    req_header = http_header_add_field(req_header, HTTP_SESSION_ID, session_id)

    local block_range
    local block_start = file_size_all - cur_left - block_size
    local block_end = file_size_all - cur_left -1
    local content_range = 'bytes' .. ' ' .. tostring(block_start) .. '-' .. tostring(block_end) .. '/' .. tostring(file_size_all)
    req_header = http_header_add_field(req_header, HTTP_CONTENT_RANGE, content_range)
    req_header = http_header_set_end(req_header)
    print('info request header:\n'..req_header)

    req_body = block
    http_request(client, req_header, req_body)

    local res_header, res_body
    res_header = {}
    res_header, res_body = http_response(client)
    --[[
        TODO
        add state machine.
    --]]
    if string.match(res_header['Connection'], 'close') then
        client:close()
        client = socket.tcp()
        client:connect(host, port)
    end

    print('info client statstics:' .. client:getstats())
end

file:close()
client:close()
