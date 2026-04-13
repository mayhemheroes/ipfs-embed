# Build Stage
FROM rustlang/rust:nightly AS builder

RUN apt-get update && apt-get install -y protobuf-compiler && rm -rf /var/lib/apt/lists/*

## Add source code to the build stage.
ADD . /src
WORKDIR /src

RUN cargo install cargo-fuzz

RUN echo building instrumented harnesses && \
    bash -c "pushd fuzz && cargo fuzz build && popd" && \
    mv fuzz/target/x86_64-unknown-linux-gnu/release/decode_block /decode_block && \
    echo done

RUN echo building non-instrumented harnesses && \
    export RUSTFLAGS="--cfg fuzzing -Clink-dead-code -Cdebug-assertions -C codegen-units=1" && \
    bash -c "pushd fuzz && cargo build --release && popd" && \
    mv fuzz/target/release/decode_block /decode_block_no_inst && \
    echo done

# Package Stage
FROM rustlang/rust:nightly

COPY --from=builder /decode_block /decode_block_no_inst /
