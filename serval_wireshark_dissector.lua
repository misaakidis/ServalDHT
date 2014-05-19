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

-- Declare Serval protocol
serval_proto = Proto("serval","SERVAL")
-- The fields table of this dissector
local f = serval_proto.fields
-- Define Serval IP Protocol number
local IPPROTO_SERVAL = 144;

-- Serval header
-- struct serval_hdr {
-- #if defined(__LITTLE_ENDIAN_BITFIELD)
-- 	uint8_t	res1:3,
--                 rsyn:1,
--                 fin:1,
--                 rst:1,
--                 ack:1,
-- 		syn:1;
-- #elif defined (__BIG_ENDIAN_BITFIELD)
-- 	uint8_t	syn:1,
--   		ack:1,
--                 rst:1,
--                 fin:1,
--                 rsyn:1,
--                 res1:3;
-- #else
-- #error	"Please fix <asm/byteorder.h>"
-- #endif
--         uint8_t  protocol;
--         uint16_t check;
--         uint16_t length;  
--         uint16_t res2;       
--         struct flow_id src_flowid;
--         struct flow_id dst_flowid;
-- } __attribute__((packed));
--
-- SERVAL_ASSERT(sizeof(struct serval_hdr) == 16)
-- #define SAL_NONCE_SIZE 8

-- Add fields to Serval table
f.flags = ProtoField.uint8("serval.flags", "Flags", base.HEX)
f.protocol = ProtoField.uint8("serval.dst_flowid", "Transfer Protocol", base.HEX)
f.check = ProtoField.uint16("serval.check", "Check", base.HEX)
f.length = ProtoField.uint16("serval.length" ,"Length", base.HEX)
f.res2 = ProtoField.uint16("serval.res2", "res2", base.HEX)
f.src_flowid = ProtoField.uint32("serval.src_flowid", "Source FlowID", base.HEX)
f.dst_flowid = ProtoField.uint32("serval.dst_flowid", "Destination FlowID", base.HEX)


-- Create a function to dissect it
function serval_proto.dissector(buffer,pinfo,tree)
    -- Dissect the header bits (Serval service access data)
    local subtree_access = tree:add(serval_proto,buffer(0,12),"Serval Service Access Data")
    	subtree_access:add(f.src_flowid,buffer(0,4))
    	subtree_access:add(f.dst_flowid,buffer(4,4))
    	subtree_access:add(f.protocol,buffer(9,1))
    	subtree_flags = subtree_access:add(buffer(10,1),"Flags")
    		subtree_flags:add(f.flags,buffer(10,1))

    -- If there are extension data, dissect them as well
    local subtree_extension = tree:add(serval_proto,buffer(12,16),"Serval Access Extension Data")
    local payload_length = buffer:len() - 32
    local payload_buffer = buffer(32, buffer:len() - 32)
    local payload = (payload_buffer):string()

    -- Finally print the payload
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