//! The last 256 KiB of the shell's output (spec §5.4 item 8): what a phone
//! sees first, including output from before the agent was reachable.

use std::collections::VecDeque;

pub const CAPACITY: usize = 256 * 1024;

pub struct RingBuffer {
    bytes: VecDeque<u8>,
    capacity: usize,
}

impl RingBuffer {
    pub fn new(capacity: usize) -> RingBuffer {
        RingBuffer {
            bytes: VecDeque::with_capacity(capacity),
            capacity,
        }
    }

    /// Appends `data`, dropping the oldest bytes beyond the capacity.
    pub fn push(&mut self, data: &[u8]) {
        let data = &data[data.len().saturating_sub(self.capacity)..];
        let overflow = (self.bytes.len() + data.len()).saturating_sub(self.capacity);
        self.bytes.drain(..overflow);
        self.bytes.extend(data);
    }

    /// Oldest to newest.
    pub fn snapshot(&self) -> Vec<u8> {
        self.bytes.iter().copied().collect()
    }

    pub fn len(&self) -> usize {
        self.bytes.len()
    }

    pub fn is_empty(&self) -> bool {
        self.bytes.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keeps_everything_below_capacity() {
        let mut r = RingBuffer::new(8);
        r.push(b"abc");
        r.push(b"de");
        assert_eq!(r.snapshot(), b"abcde");
    }

    #[test]
    fn drops_the_oldest_bytes() {
        let mut r = RingBuffer::new(8);
        r.push(b"abcdef");
        r.push(b"ghij");
        assert_eq!(r.snapshot(), b"cdefghij");
        assert_eq!(r.len(), 8);
    }

    #[test]
    fn a_huge_push_keeps_its_tail() {
        let mut r = RingBuffer::new(4);
        r.push(b"x");
        r.push(b"0123456789");
        assert_eq!(r.snapshot(), b"6789");
    }

    #[test]
    fn default_capacity_is_256_kib() {
        let mut r = RingBuffer::new(CAPACITY);
        r.push(&vec![1u8; CAPACITY + 10]);
        assert_eq!(r.len(), 262_144);
    }
}
