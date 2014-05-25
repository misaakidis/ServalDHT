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

-- Define Serval IP Protocol number
local IPPROTO_SERVAL = 144;

-- Define constants for Serval
local SAL_HDR_LEN = 12
local SAL_EXT_LEN = 2
local MAX_NUM_SAL_EXTENSIONS = 10

local TCP_HDR_LEN = 20

-- Define Extension types
local SAL_PAD_EXT = 0x00
local SAL_CONTROL_EXT = 0x01
local SAL_SERVICE_EXT = 0x02
local SAL_ADDRESS_EXT = 0x03
local SAL_SOURCE_EXT = 0x04


-- Declare Serval protocol
serval_proto = Proto("serval","SERVAL")

-- The fields table of this dissector
local f = serval_proto.fields
-- Add fields to Serval table, as to be presented in Packet Details
f.src_flowid = ProtoField.uint32("serval.src_flowid", "Source FlowID", base.HEX)
f.dst_flowid = ProtoField.uint32("serval.dst_flowid", "Destination FlowID", base.HEX)
f.shl = ProtoField.uint8("serval.shl" ,"SAL Header Length (in 32bit words)", base.DEC)
f.protocol = ProtoField.uint8("serval.protocol", "Transfer Protocol (TCP=6, UDP=17)", base.DEC)
f.check = ProtoField.uint16("serval.check", "Check", base.HEX)
f.sal_ext = ProtoField.bytes("serval.ext", "Extension", base.HEX)
f.sal_ext_typeres = ProtoField.uint8("serval.ext_typeres", "Extension TypeRes", base.HEX)
f.sal_ext_length = ProtoField.uint8("serval.ext_length", "Extension Length", base.DEC)
f.sal_ext_data = ProtoField.bytes("serval.ext_data", "Extension Data", base.HEX)

-- Transport Layer fields
f.tcp_src_port = ProtoField.uint16("serval.tcp_src_port", "Source Port", base.DEC)
f.tcp_dst_port = ProtoField.uint16("serval.tcp_dst_port", "Destination Port", base.DEC)
f.tcp_seq = ProtoField.uint32("serval.tcp_seq", "Sequence number", base.DEC)
f.tcp_ack = ProtoField.uint32("serval.tcp_ack", "Acknowledge number", base.DEC)
f.tcp_data_offset = ProtoField.uint8("serval.tcp_data_offset", "Data Offset", base.DEC)
-- f.tcp_reserved
-- f.tcp_flags
-- f.tcp_window_size
-- f.tcp_check
-- f.tcp_urg
f.tcp_options = ProtoField.bytes("serval.tcp_options", "Options", base.HEX)


-- Create a function to dissect Serval
function serval_proto.dissector(buffer,pinfo,tree)
    pinfo.cols.protocol = "Serval"
    local transport_protocol = 0

    -- Dissect the SAL header bits (Serval Access Layer header)
    local subtree_access = tree:add(serval_proto,buffer(0,SAL_HDR_LEN),"Serval SAL Header")
    	subtree_access:add(f.src_flowid,buffer(0,4))
    	subtree_access:add(f.dst_flowid,buffer(4,4))
        
        subtree_access:add(f.shl,buffer(8,1))
        -- Calculate the Extensions Header length
        local ext_hdr_len = buffer(8,1):uint()*4 - SAL_HDR_LEN
    	
        subtree_access:add(f.protocol,buffer(9,1))
        transport_protocol = buffer(9,1):uint()
        subtree_access:add(f.check,buffer(10,2))

    -- If there are extension data, dissect them as well
    if ext_hdr_len > 0 then
        local i = 0
        local ext_hdr_consumed = 0
        local ext_type
        local type_msg
        local ext_length

        local subtree_extension = tree:add(serval_proto,buffer(SAL_HDR_LEN,ext_hdr_len),"Serval Extension Headers (" .. ext_hdr_len .. " bytes)")
        while (ext_hdr_len > ext_hdr_consumed and i < MAX_NUM_SAL_EXTENSIONS) do

            ext_length = 0
            ext_type = buffer(SAL_HDR_LEN+ext_hdr_consumed,1):bitfield(0,4)

            if ext_type == SAL_PAD_EXT then
                type_msg = "PAD"
                ext_length = 1

                local sub_ext_tree = subtree_extension:add(serval_proto,buffer(SAL_HDR_LEN+ext_hdr_consumed,1),"Serval Extension: " .. type_msg .. " (" .. ext_hdr_consumed .. "," .. ext_hdr_consumed+ext_length .. ")")
                    sub_ext_tree:add(f.sal_ext_typeres, buffer(SAL_HDR_LEN+ext_hdr_consumed,1))

            else
                ext_length = buffer(SAL_HDR_LEN+ext_hdr_consumed+1,1):uint()    
                if ext_type == SAL_CONTROL_EXT then
                    type_msg = "CONTROL"
                    ext_length = 20
                elseif ext_type == SAL_SERVICE_EXT then
                    type_msg = "SERVICE"
                    ext_length = 36
                elseif ext_type == SAL_ADDRESS_EXT then
                    type_msg = "ADDRESS"
                    ext_length = 12
                elseif ext_type == SAL_SOURCE_EXT then
                    type_msg = "SOURCE"
                else
                    type_msg = "???"
                end

                local sub_ext_tree = subtree_extension:add(serval_proto,buffer(SAL_HDR_LEN+ext_hdr_consumed,ext_length),"Serval Extension: " .. type_msg .. " (" .. ext_hdr_consumed .. "," .. ext_hdr_consumed+ext_length .. ")")
                    sub_ext_tree:add(f.sal_ext_typeres, buffer(SAL_HDR_LEN+ext_hdr_consumed,1))
                    sub_ext_tree:add(f.sal_ext_length, buffer(SAL_HDR_LEN+ext_hdr_consumed+1,1)) 
                    sub_ext_tree:add(f.sal_ext_data, buffer(SAL_HDR_LEN+ext_hdr_consumed+2,ext_length-2))  
            end

            i = i + 1
            ext_hdr_consumed = ext_hdr_consumed + ext_length

        end
    end

    -- Transport Protocol Specific headers
    local transport_hdr_len = 0
    -- If Protocol is TCP
    if transport_protocol == 6 then
        local data_offset = buffer(SAL_HDR_LEN+ext_hdr_len+12, 1):bitfield(0,4)
        transport_hdr_len = data_offset * 4
        local subtree_protocol = tree:add(serval_proto,buffer(SAL_HDR_LEN+ext_hdr_len,transport_hdr),"Transmission Control Protocol: " .. transport_hdr_len .. " bytes")
            subtree_protocol:add(f.tcp_data_offset, buffer(SAL_HDR_LEN+ext_hdr_len+12, 1))
            if transport_hdr_len > TCP_HDR_LEN then
                subtree_protocol:add(f.tcp_options, buffer(SAL_HDR_LEN+ext_hdr_len+TCP_HDR_LEN, transport_hdr_len-TCP_HDR_LEN))
            end
    end

    -- Finally print the payload
    local payload_length = buffer:len() - SAL_HDR_LEN - ext_hdr_len - transport_hdr_len
    if payload_length > 0 then
        local payload_buffer = buffer(SAL_HDR_LEN+ext_hdr_len+transport_hdr_len, payload_length)
        local payload = payload_buffer:string()
        local subtree_payload = tree:add(serval_proto, payload_buffer, "Payload: " .. payload_length .. " bytes")
            subtree_payload:add(payload)

        -- Change the content of column payload (up to 80 chars and trimmed newlines)
        pinfo.cols.info = string.gsub(payload:sub(1, 80), "\n", "")
    end

end

function serval_proto.init()
end

-- Load the ip.proto table
local ip_proto_table = DissectorTable.get("ip.proto")
-- Register our protocol to handle IPPROTO_SERVAL (144)
ip_proto_table:add(IPPROTO_SERVAL,serval_proto)