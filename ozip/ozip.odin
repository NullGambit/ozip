package ozip

import "core:os/os2"
import "core:strings"
import "core:path/slashpath"
import "core:compress"
import "core:bytes"
import "core:compress/zlib"
import "core:mem/virtual"
import "core:fmt"
import "core:os"

// in reverse so can be read from the end of the file
@(private = "package")
MAGIC_NUMBER :: []u8{0x06, 0x05, 0x4B, 0x50}

CD_COMP_METHOD :: 10
CD_FILENAME_LEN :: 28
CD_FILENAME :: 46
CD_EXTRA_FIELD_LEN :: 30
CD_COMPRESSED_SIZE :: 20
CD_FILE_HEADER_OFFSET :: 42

// offset in the local file header of the extra field len field
LFH_EXTRA_FIELD_LEN :: 30

// supported compression methods in ozip. currently only supporting deflate because 90% of the times its the only one used
CompressionMethod :: enum (i16) 
{
    Store,
    Deflate = 8,
}

CentralDirectoryHeader :: struct #packed
{
    magic_number: i32,
    version_made_by: i16,
    version_needed: i16,
    general_purpose_flag: i16,
    compression_method: CompressionMethod,
    last_modified_time: i16,
    last_modified_date: i16,
    CRC32: i32,
    compressed_size: i32,
    uncompressed_size: i32,
    filename_len: i16,
    extra_field_len: i16,
    file_comment_len: i16,
    disk_number: i16,
    internal_attributes: i16,
    external_attributes: i32,
    file_header_offset: i32,
}

LocalFileHeader :: struct #packed
{
    magic_number: i32,
    version_needed: i16,
    general_purpose_flag: i16,
    compression_method: CompressionMethod,
    last_modified_time: i16,
    last_modified_date: i16,
    CRC32: i32,
    compressed_size: i32,
    uncompressed_size: i32,
    filename_len: i16,
    extra_field_len: i16,
}

File :: struct 
{
    header: ^LocalFileHeader,
    cd_header: ^CentralDirectoryHeader,
    offset: i32,
}

Error :: enum 
{
    None,
    InvalidEocd,
    EntryNotFound
}

ReadEntryError :: union #shared_nil
{
    Error,
    compress.Error
} 

ZipDir :: struct 
{
    data: []byte ,
    local_files: map[string]File,
}

find_eocd :: proc(data: []byte) -> (u64, Error)
{
    magic_numbers := MAGIC_NUMBER
    magic_number_cursor := 0

    for i := cast(u64)len(data)-1; i > 0; i -= 1 
    {
        c := data[i]

        if c == magic_numbers[magic_number_cursor]
        {
            magic_number_cursor += 1
        }

        if len(magic_numbers) == magic_number_cursor
        {
            // + 6 to read past magic number
            return i + 4, .None
        }
    }

    return 0, .InvalidEocd
}

open :: proc(filename: string, allocator := context.allocator) -> (dir: ZipDir, out_err: Error)
{
    data, err := virtual.map_file(filename, {.Read, .Write})

    if err != .None
    {
        return {}, .None
    }

    eocd_start := find_eocd(data) or_return

    reader := Reader {
        data = data,
        // + 6 skips past some irrelevant fields
        offset = eocd_start + 6
    }

    cd_count := read_int(&reader, i16) 

    size := read_int(&reader, i32)
    offset := u64(read_int(&reader, u32))

    dir.local_files = make(map[string]File, allocator)

    for i in 0..<cd_count 
    {
        cd_buff := data[offset:offset+CD_FILE_HEADER_OFFSET]

        cd := cast(^CentralDirectoryHeader)raw_data(cd_buff)

        offset += CD_FILENAME

        filename := string(data[offset:offset+u64(cd.filename_len)])

        offset += u64(cd.extra_field_len + cd.file_comment_len + cd.filename_len)

        local_file_buff := data[cd.file_header_offset:cd.file_header_offset+LFH_EXTRA_FIELD_LEN]

        if cd.compressed_size > 0
        {
            dir.local_files[filename] = File {
                header = cast(^LocalFileHeader)raw_data(local_file_buff),
                cd_header = cd,
                offset = cd.file_header_offset
            }
        }
    }

    dir.data = data

    return
}

UnpackError :: union #shared_nil 
{
    compress.Error,
    os2.Error
}

unpack :: proc(dir: ZipDir, dest: string, allocator := context.allocator) -> UnpackError
{
    if !os2.exists(dest)
    {
        os2.mkdir(dest) or_return
    }

    for filename, file in dir.local_files
    {
        // TODO: optimize it by writing to one giant file buffer
        data, was_allocation := read_entry_from_file(dir, file) or_return

        defer if was_allocation 
        {
            delete(data)
        }

        file_path := os2.join_path({dest, filename}, allocator) or_return

        defer delete(file_path)

        index := strings.last_index(file_path, "/")

        path_dir := file_path[:index]

        if !os2.exists(path_dir)
        {
            os2.mkdir(path_dir) or_return
        }

        os2.write_entire_file(file_path, data) or_return
    }

    return nil
}

close :: proc(dir: ^ZipDir)
{
    virtual.release(raw_data(dir.data), len(dir.data))
    dir.data = nil
    delete(dir.local_files)
}

@(private)
read_entry_from_file :: proc(dir: ZipDir, file: File) -> ([]byte, bool, compress.Error)
{
    offset := file.offset + LFH_EXTRA_FIELD_LEN + i32(file.header.extra_field_len + file.header.filename_len)

    if file.header.compression_method == .Store 
    {
        return dir.data[offset:offset+file.header.uncompressed_size], false, nil
    }

    data := dir.data[offset:offset+file.cd_header.compressed_size]

    buff: bytes.Buffer

    err := zlib.inflate(data, &buff, raw=true, expected_output_size=int(file.cd_header.uncompressed_size))

    return buff.buf[:], true, err 
}

read_entry :: proc(dir: ZipDir, filename: string) -> ([]byte, bool, ReadEntryError)
{
    file, exists := dir.local_files[filename]

    if !exists 
    {
        return nil, false, .EntryNotFound
    }

    return read_entry_from_file(dir, file)
}