use alexandria_data_structures::array_ext::ArrayTraitExt;
use alexandria_math::BitShift;
use core::num::traits::Bounded;

pub trait Encoder<T> {
    fn encode(data: T) -> Array<u8>;
}

pub trait Decoder<T> {
    fn decode(data: T) -> Array<u8>;
}

pub impl Base64Encoder of Encoder<Array<u8>> {
    fn encode(data: Array<u8>) -> Array<u8> {
        let mut char_set = get_base64_char_set();
        char_set.append('+');
        char_set.append('/');
        encode_u8_array(data, char_set.span())
    }
}

pub impl Base64UrlEncoder of Encoder<Array<u8>> {
    fn encode(data: Array<u8>) -> Array<u8> {
        let mut char_set = get_base64_char_set();
        char_set.append('-');
        char_set.append('_');
        encode_u8_array(data, char_set.span())
    }
}

pub impl Base64FeltEncoder of Encoder<felt252> {
    fn encode(data: felt252) -> Array<u8> {
        let mut char_set = get_base64_char_set();
        char_set.append('+');
        char_set.append('/');
        encode_felt(data, char_set.span())
    }
}

pub impl Base64UrlFeltEncoder of Encoder<felt252> {
    fn encode(data: felt252) -> Array<u8> {
        let mut char_set = get_base64_char_set();
        char_set.append('-');
        char_set.append('_');
        encode_felt(data, char_set.span())
    }
}

pub fn encode_u8_array(mut bytes: Array<u8>, base64_chars: Span<u8>) -> Array<u8> {
    let mut result = array![];
    if bytes.len() == 0 {
        return result;
    }

    // Handle padding calculation upfront
    let mut p: u8 = 0;
    let c = bytes.len() % 3;
    if c == 1 {
        p = 2;
        bytes.append(0_u8);
        bytes.append(0_u8);
    } else if c == 2 {
        p = 1;
        bytes.append(0_u8);
    }

    let mut i = 0;
    let bytes_len = bytes.len();
    let last_iteration = bytes_len - 3;

    while i < bytes_len {
        // Calculate the 24-bit group (3 bytes at a time)
        let b1: u32 = (*bytes[i]).into() * 65536;
        let b2: u32 = (*bytes[i + 1]).into() * 256;
        let b3: u32 = (*bytes[i + 2]).into();
        let n: u32 = b1 | b2 | b3;

        // Extract the four 6-bit values using division and masking
        let e1 = (n / 262144) & 63;
        let e2 = (n / 4096) & 63;
        let e3 = (n / 64) & 63;
        let e4 = n & 63;

        // Add the encoded characters
        result.append(*base64_chars[e1]);
        result.append(*base64_chars[e2]);

        // Handle padding for the last group
        if i == last_iteration {
            if p == 2 {
                result.append('=');
                result.append('=');
            } else if p == 1 {
                result.append(*base64_chars[e3]);
                result.append('=');
            } else {
                result.append(*base64_chars[e3]);
                result.append(*base64_chars[e4]);
            }
        } else {
            result.append(*base64_chars[e3]);
            result.append(*base64_chars[e4]);
        }

        i += 3;
    }

    result
}

pub fn encode_felt(self: felt252, base64_chars: Span<u8>) -> Array<u8> {
    let mut result = array![];

    let mut num: u256 = self.into();
    // Special case for zero
    if num == 0 {
        // Create a result with the minimum padding
        result.append(*base64_chars[0]); // 'A'

        // Pad to 43 characters
        let pad_count = 42; // We already added one 'A', so add 42 more for a total of 43
        let mut i = 0;
        while i != pad_count {
            result.append(*base64_chars[0]);
            i += 1;
        }

        result.append('='); // Add padding
        return result;
    }

    // Handle non-zero values
    let (quotient, remainder) = DivRem::div_rem(num, 65536_u256.try_into().unwrap());
    // Safe since 'remainder' is always less than 65536 (2^16),
    // which is within the range of usize (less than 2^32).
    let remainder: usize = remainder.try_into().unwrap();

    // Optimize bit operations
    let r1 = (remainder * 4) & 63;
    let r2 = (remainder / 16) & 63;
    let r3 = (remainder / 1024) & 63;

    result.append(*base64_chars[r1]);
    result.append(*base64_chars[r2]);
    result.append(*base64_chars[r3]);

    num = quotient;

    while num != 0 {
        let (quotient, remainder) = DivRem::div_rem(num, 16777216_u256.try_into().unwrap());
        // Safe since 'remainder' is always less than 16777216 (2^24),
        // which is within the range of usize (less than 2^32).
        let remainder: usize = remainder.try_into().unwrap();

        // Optimize bit operations
        let r1 = remainder & 63;
        let r2 = (remainder / 64) & 63;
        let r3 = (remainder / 4096) & 63;
        let r4 = remainder / 262144;

        result.append(*base64_chars[r1]);
        result.append(*base64_chars[r2]);
        result.append(*base64_chars[r3]);
        result.append(*base64_chars[r4]);

        num = quotient;
    }

    // Padding with 'A's to ensure length is 43
    let required_length = 43;
    let current_length = result.len();
    if current_length < required_length {
        let padding_len = required_length - current_length;
        let mut i = 0;
        while i != padding_len {
            result.append(*base64_chars[0]); // 'A'
            i += 1;
        }
    }

    result = result.reversed();
    result.append('=');

    result
}

pub impl Base64Decoder of Decoder<Array<u8>> {
    fn decode(data: Array<u8>) -> Array<u8> {
        inner_decode(data)
    }
}

pub impl Base64UrlDecoder of Decoder<Array<u8>> {
    fn decode(data: Array<u8>) -> Array<u8> {
        inner_decode(data)
    }
}

fn inner_decode(data: Array<u8>) -> Array<u8> {
    let mut result = array![];

    // Early return for empty input
    if data.len() == 0 {
        return result;
    }

    // Calculate padding
    let mut p = 0_u8;
    let data_len = data.len();

    // Check for padding characters ('=')
    if data_len > 0 && *data[data_len - 1] == '=' {
        p += 1;

        if data_len > 1 && *data[data_len - 2] == '=' {
            p += 1;
        }
    }

    // Process data in groups of 4 characters
    let mut i = 0;
    while i + 3 < data_len {
        // Get values for the 4 characters
        let v1: u32 = get_base64_value(*data[i]).into();
        let v2: u32 = get_base64_value(*data[i + 1]).into();
        let v3: u32 = get_base64_value(*data[i + 2]).into();
        let v4: u32 = get_base64_value(*data[i + 3]).into();

        // Combine the 4 6-bit values into a 24-bit number
        let combined: u32 = (v1 * 262144) + (v2 * 4096) + (v3 * 64) + v4;

        // Extract the 3 bytes
        let b1: u8 = ((combined / 65536) & 0xFF).try_into().unwrap();
        result.append(b1);

        // Handle padding - don't add bytes if we're at the end with padding
        if i + 4 >= data_len && p == 2 {
            break;
        }

        let b2: u8 = ((combined / 256) & 0xFF).try_into().unwrap();
        result.append(b2);

        if i + 4 >= data_len && p == 1 {
            break;
        }

        let b3: u8 = (combined & 0xFF).try_into().unwrap();
        result.append(b3);

        i += 4;
    }

    result
}

fn get_base64_value(x: u8) -> u8 {
    // Fast lookup based on ASCII values
    if x == '+' || x == '-' {
        return 62;
    }

    if x == '/' || x == '_' {
        return 63;
    }

    if x >= 'A' && x <= 'Z' {
        return x - 'A';
    }

    if x >= 'a' && x <= 'z' {
        return (x - 'a') + 26;
    }

    if x >= '0' && x <= '9' {
        return (x - '0') + 52;
    }

    // '=' padding character or any other character
    return 0;
}

fn get_base64_char_set() -> Array<u8> {
    array![
        'A',
        'B',
        'C',
        'D',
        'E',
        'F',
        'G',
        'H',
        'I',
        'J',
        'K',
        'L',
        'M',
        'N',
        'O',
        'P',
        'Q',
        'R',
        'S',
        'T',
        'U',
        'V',
        'W',
        'X',
        'Y',
        'Z',
        'a',
        'b',
        'c',
        'd',
        'e',
        'f',
        'g',
        'h',
        'i',
        'j',
        'k',
        'l',
        'm',
        'n',
        'o',
        'p',
        'q',
        'r',
        's',
        't',
        'u',
        'v',
        'w',
        'x',
        'y',
        'z',
        '0',
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '7',
        '8',
        '9',
    ]
}
