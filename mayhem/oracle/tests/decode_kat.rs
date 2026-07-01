// Known-answer tests for the code path exercised by the decode-block fuzzer:
// ipfs_embed::Block::decode over the libipld DagCbor / Raw / DagJson codecs.
// These assert DECODED VALUES, so a patch that neuters decoding (e.g. returns
// Ok(default) / exits early) fails here — this is the anti-reward-hack oracle.
use cid::Cid;
use ipfs_embed::Block;
use libipld::{cbor::DagCborCodec, json::DagJsonCodec, store::DefaultParams, Ipld, IpldCodec};

fn block(codec: IpldCodec, data: Vec<u8>) -> Block<DefaultParams> {
    // new_unchecked mirrors the fuzz harness (hashes aren't forged); codec drives decode.
    let cid = Cid::new_v1(codec.into(), Default::default());
    Block::new_unchecked(cid, data)
}

#[test]
fn dagcbor_integer_kat() {
    // DagCbor: 0x01 encodes the unsigned integer 1.
    let b = block(IpldCodec::DagCbor, vec![0x01]);
    let v = b.decode::<DagCborCodec, Ipld>().expect("valid DagCbor int decodes");
    assert_eq!(v, Ipld::Integer(1));
}

#[test]
fn dagcbor_bytestring_kat() {
    // DagCbor: 0x43 0x01 0x02 0x03 = byte string of length 3 {01,02,03}.
    let b = block(IpldCodec::DagCbor, vec![0x43, 0x01, 0x02, 0x03]);
    let v = b.decode::<DagCborCodec, Ipld>().expect("valid DagCbor bytes decode");
    assert_eq!(v, Ipld::Bytes(vec![0x01, 0x02, 0x03]));
}

#[test]
fn dagcbor_array_kat() {
    // DagCbor: 0x82 0x01 0x02 = array [1, 2].
    let b = block(IpldCodec::DagCbor, vec![0x82, 0x01, 0x02]);
    let v = b.decode::<DagCborCodec, Ipld>().expect("valid DagCbor array decodes");
    assert_eq!(v, Ipld::List(vec![Ipld::Integer(1), Ipld::Integer(2)]));
}

#[test]
fn raw_bytes_kat() {
    // Raw codec: the payload IS the bytes, verbatim.
    let payload = vec![0xde, 0xad, 0xbe, 0xef];
    let b = block(IpldCodec::Raw, payload.clone());
    let v = b.decode::<IpldCodec, Ipld>().expect("raw bytes decode");
    assert_eq!(v, Ipld::Bytes(payload));
}

#[test]
fn dagjson_object_kat() {
    // DagJson: {"a":1} -> Ipld map { "a": Integer(1) }.
    let b = block(IpldCodec::DagJson, br#"{"a":1}"#.to_vec());
    let v = b.decode::<DagJsonCodec, Ipld>().expect("valid DagJson decodes");
    let mut expected = std::collections::BTreeMap::new();
    expected.insert("a".to_string(), Ipld::Integer(1));
    assert_eq!(v, Ipld::Map(expected));
}

#[test]
fn dagcbor_garbage_is_rejected() {
    // A clearly-invalid DagCbor stream must FAIL to decode (not silently succeed).
    // 0x9f = indefinite-length array start with no terminator -> error.
    let b = block(IpldCodec::DagCbor, vec![0x9f, 0xff, 0xff, 0xff]);
    let r = b.decode::<DagCborCodec, Ipld>();
    assert!(r.is_err(), "malformed DagCbor must be rejected, got {:?}", r);
}
