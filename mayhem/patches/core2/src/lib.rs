pub mod io {
    pub use std::io::{BufRead, Cursor, Error, ErrorKind, Read, Result, Seek, SeekFrom, Write};
}
pub mod error {
    pub use std::error::Error;
}
