package ozip

Reader :: struct 
{
    offset: u64,
    data: []byte,
}

read_int :: proc(reader: ^Reader, $T: typeid) -> T 
{
    N :: size_of(T)

    buffer := [N]byte{}

    copy(buffer[:], reader.data[reader.offset:])

    reader.offset += N

    return transmute(T)buffer
}

read_int_ptr :: proc(reader: ^Reader, $T: typeid) -> ^T 
{
    offset := reader.offset 

    reader.offset += size_of(T)

    return cast(^T)raw_data(reader.data[offset:offset+size_of(T)])
}