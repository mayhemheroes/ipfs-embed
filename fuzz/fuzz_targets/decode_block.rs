#![no_main]
use cid::Cid;
use ipfs_embed::Block;
use libfuzzer_sys::fuzz_target;
use libipld::{
    cbor::DagCborCodec, json::DagJsonCodec, pb::DagPbCodec, raw_value::IgnoredAny,
    store::DefaultParams, Ipld, IpldCodec, Link,
};

fuzz_target!(|data: Vec<u8>| {
    let _ = fuzz(data);
});

fn fuzz(data: Vec<u8>) -> Result<(), ()> {
    // Note: we use `new_unchecked` because fuzzers can't forge hashes

    // Cbor
    let cid = Cid::new_v1(IpldCodec::DagCbor.into(), Default::default());
    let block: Block<DefaultParams> = Block::new_unchecked(cid, data.clone());
    let _ = block.decode::<DagCborCodec, Ipld>();
    let _ = block.decode::<DagCborCodec, Link<()>>();
    let _ = block.decode::<DagCborCodec, IgnoredAny>();
    let _ = block.decode::<DagCborCodec, Cid>();
    let _ = block.decode::<DagCborCodec, ()>();

    // Raw
    let cid = Cid::new_v1(IpldCodec::Raw.into(), Default::default());
    let block: Block<DefaultParams> = Block::new_unchecked(cid, data.clone());
    let _ = block.decode::<IpldCodec, Ipld>();

    // Pb
    let cid = Cid::new_v1(IpldCodec::DagPb.into(), Default::default());
    let block: Block<DefaultParams> = Block::new_unchecked(cid, data.clone());
    let _ = block.decode::<DagPbCodec, Ipld>();

    // Json
    let cid = Cid::new_v1(IpldCodec::DagJson.into(), Default::default());
    let block: Block<DefaultParams> = Block::new_unchecked(cid, data);
    let _ = block.decode::<DagJsonCodec, Ipld>();

    Ok(())
}
