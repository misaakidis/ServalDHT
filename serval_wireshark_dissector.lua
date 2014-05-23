-- 
-- Serval protocol dissector for wireshark
-- 
-- Authors: Marios Isaakidis <misaakidis@yahoo.gr
-- 
-- This program is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License as
-- published by the Free Software Foundation; either version 2 of
-- the License, or (at your option) any later version.
-- 

require("bit")

local SAL_PAD_EXT = 0x00
local SAL_CONTROL_EXT = 0x01
local SAL_SERVICE_EXT = 0x02
local SAL_ADDRESS_EXT = 0x03
local SAL_SOURCE_EXT = 0x04

-- Declare Serval protocol
serval_proto = Proto("serval","SERVAL")
-- The fields table of this dissector
local f = serval_proto.fields
-- Define Serval IP Protocol number
local IPPROTO_SERVAL = 144;

-- Add fields to Serval table
f.src_flowid = ProtoField.uint32("serval.src_flowid", "Source FlowID", base.HEX)
f.dst_flowid = ProtoField.uint32("serval.dst_flowid", "Destination FlowID", base.HEX)
f.shl = ProtoField.uint8("serval.shl" ,"SAL Header Length (in 32bit words)", base.DEC)
f.protocol = ProtoField.uint8("serval.dst_flowid", "Transfer Protocol", base.HEX)
f.check = ProtoField.uint16("serval.check", "Check", base.HEX)
f.sal_ext = ProtoField.bytes("serval.ext", "Extension", base.HEX)
f.sal_ext_typeres = ProtoField.uint8("serval.ext_typeres", "Extension TypeRes", base.HEX)
f.sal_ext_length = ProtoField.uint8("serval.ext_length", "Extension Length", base.HEX)
f.sal_ext_data = ProtoField.bytes("serval.ext_data", "Extension Data", base.HEX)


local SAL_HDR_LEN = 12
local SAL_EXT_LEN = 2
local MAX_NUM_SAL_EXTENSIONS = 10

-- Create a function to dissect it
function serval_proto.dissector(buffer,pinfo,tree)
    -- Dissect the SAL header bits (Serval Access Layer header)
    local subtree_access = tree:add(serval_proto,buffer(0,SAL_HDR_LEN),"Serval SAL Header")
    	subtree_access:add(f.src_flowid,buffer(0,4))
    	subtree_access:add(f.dst_flowid,buffer(4,4))
        
        subtree_access:add(f.shl,buffer(8,1))
        local ext_hdr_len = buffer(8,1):uint()*4 - SAL_HDR_LEN
    	
        subtree_access:add(f.protocol,buffer(9,1))
        subtree_access:add(f.check,buffer(10,2))

    -- If there are extension data, dissect them as well
    local i = 0
    local ext_hdr_consumed = 0

    local subtree_extension = tree:add(serval_proto,buffer(SAL_HDR_LEN,ext_hdr_len),"Serval Extension Headers (" .. ext_hdr_len .. " bytes)")
    while (ext_hdr_len > ext_hdr_consumed and i < MAX_NUM_SAL_EXTENSIONS) do
        
        local ext_type = buffer(ext_hdr_consumed,1):bitfield(0,4)
        local ext_length = buffer(ext_hdr_consumed+1,1):uint()
        
        local type_msg
        if ext_type == SAL_PAD_EXT then
            type_msg = "PAD"
        elseif ext_type == SAL_CONTROL_EXT then
            type_msg = "CONTROL"
        elseif ext_type == SAL_SERVICE_EXT then
            type_msg = "SERVICE"
        elseif ext_type == SAL_ADDRESS_EXT then
            type_msg = "ADDRESS"
        elseif ext_type == SAL_SOURCE_EXT then
            type_msg = "SOURCE"
        else
            type_msg = "???"
        end

        if ext_type == SAL_PAD_EXT then 
            ext_length = 1
        end

        local sub_ext_tree = subtree_extension:add(serval_proto,buffer(ext_hdr_consumed,ext_length+2),"Serval Extension: " .. type_msg .. " (" .. ext_hdr_consumed .. "," .. ext_hdr_consumed+ext_length+1 .. ")")
            sub_ext_tree:add(f.sal_ext_typeres, buffer(ext_hdr_consumed,1))
            sub_ext_tree:add(f.sal_ext_length, buffer(ext_hdr_consumed+1,1))
            -- subtree_extension:add(f.sal_ext_data, buffer(2,ext_length))

        i = i + 1
        ext_hdr_consumed = ext_hdr_consumed + ext_length + 2

    end

    -- Find Serval Access Extension Data length
    --

    -- Finally print the payload
    local payload_length = buffer:len() - SAL_HDR_LEN - ext_hdr_len
    local payload_buffer = buffer(SAL_HDR_LEN+ext_hdr_len, payload_length)
    local payload = payload_buffer:string()
    local subtree_payload = tree:add(serval_proto, payload_buffer, "Payload: " .. payload_length .. " bytes")
        subtree_payload:add(payload)
    
    -- Change the content of columns, add Protocol name and payload (up to 80 chars and trimmed newlines)
    pinfo.cols.protocol = "Serval"
    pinfo.cols.info = string.gsub(payload:sub(1, 80), "\n", "")
end

function serval_proto.init()
end

-- Load the ip.proto table
local ip_proto_table = DissectorTable.get("ip.proto")
-- Register our protocol to handle IPPROTO_SERVAL
ip_proto_table:add(IPPROTO_SERVAL,serval_proto)