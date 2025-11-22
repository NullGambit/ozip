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

    // ozip.unpack(dir, "./archive")

    my_file, was_allocation, entry_err := ozip.read_entry(dir, "ols.json")

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