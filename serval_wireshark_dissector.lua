-- Serval protocol dissector for wireshark

-- declare our protocol
serval_proto = Proto("serval","SERVAL")
local f = serval_proto.fields

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

f.flags = ProtoField.uint8("serval.flags", "Flags", base.HEX)
f.protocol = ProtoField.uint8("serval.dst_flowid", "Transfer Protocol", base.HEX)
f.check = ProtoField.uint16("serval.check", "Check", base.HEX)
f.length = ProtoField.uint16("serval.length" ,"Length", base.HEX)
f.res2 = ProtoField.uint16("serval.res2", "res2", base.HEX)
f.src_flowid = ProtoField.uint32("serval.src_flowid", "Source FlowID", base.HEX)
f.dst_flowid = ProtoField.uint32("serval.dst_flowid", "Destination FlowID", base.HEX)


-- create a function to dissect it
function serval_proto.dissector(buffer,pinfo,tree)
    local subtree_access = tree:add(serval_proto,buffer(0,12),"Serval Service Access Data")
    	subtree_access:add(f.src_flowid,buffer(0,4))
    	subtree_access:add(f.dst_flowid,buffer(4,4))
    	subtree_access:add(f.protocol,buffer(9,1))
    	subtree_flags = subtree_access:add(buffer(10,1),"Flags")
    		subtree_flags:add(f.flags,buffer(10,1))
    local subtree_extension = tree:add(serval_proto,buffer(12,16),"Serval Access Extension Data")
    local subtree_payload = tree:add(serval_proto, buffer(32, buffer:len() - 32), "Payload: " .. buffer:len() - 32 .. " bytes")
    local payload = (buffer(32, buffer:len() - 32)):string()
    pinfo.cols.info = string.gsub(payload:sub(1, 80), "\n", "")
end
-- string.format("%X", 
function serval_proto.init()
 	-- load the ip.proto table
 	ip_proto_table = DissectorTable.get("ip.proto")
	-- register our protocol to handle ip protocol 144
 	ip_proto_table:add(144,serval_proto)
end