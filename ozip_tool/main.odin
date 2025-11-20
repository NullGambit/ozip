package main 

import "core:fmt"
import "../ozip"

main :: proc()
{
    dir, err := ozip.open("Archive.zip")

    defer ozip.close(&dir)

    if err != .None
    {
        fmt.println("could not open archive", err)
        return
    }

    my_file, entry_err, was_allocation := ozip.read_entry(dir, "ozip_tool/main.odin")

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