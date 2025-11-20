# Ozip

I wrote ozip because i noticed there weren't any zip implementation written in odin and i wanted to contribute to the ecosystem and also because i really wanted to know how zip works.

## Example

```odin
main :: proc()
{
    dir, err := ozip.open("Archive.zip")

    defer ozip.close(&dir)

    if err != .None
    {
        fmt.println("could not open archive", err)
        return
    }

    my_file, entry_err, was_allocation := ozip.read_entry(dir, "path/to_my_file.txt")

    if entry_err != nil 
    {
        fmt.println("error reading entry", entry_err)
        return
    }

    defer if was_allocation 
    {
        delete(my_file)
    }

    fmt.println(string(my_file))
}
```