package main

import "core:fmt"
import "core:os"
import "core:encoding/json"
import "core:intrinsics"
import "core:sys/unix"
import "core:strings"

fzf :: proc{
    fzf_unix,
}

fzf_unix :: proc(options: []string) -> string {
    pipefd : [2]i32 = {0, 0}
    res := intrinsics.syscall(unix.SYS_pipe, uintptr(&pipefd))

    backpipefd : [2]i32 = {0, 0}
    res = intrinsics.syscall(unix.SYS_pipe, uintptr(&backpipefd))

    p := i32(intrinsics.syscall(unix.SYS_fork))

    option_selected := ""

    if p == 0 {
        res = intrinsics.syscall(unix.SYS_close, uintptr(pipefd[1]));
        res = intrinsics.syscall(unix.SYS_dup2, uintptr(pipefd[0]), 0);
        res = intrinsics.syscall(unix.SYS_close, uintptr(pipefd[0]));

        res = intrinsics.syscall(unix.SYS_close, uintptr(backpipefd[0]));
        res = intrinsics.syscall(unix.SYS_dup2, uintptr(backpipefd[1]), 1);
        res = intrinsics.syscall(unix.SYS_close, uintptr(backpipefd[1]));

        fzf_argv := []cstring{ "/usr/bin/fzf", nil }
        fzf : cstring = "/usr/bin/fzf"

        res = intrinsics.syscall(unix.SYS_execve, uintptr(rawptr(fzf)), uintptr(&fzf_argv[0]), uintptr(&[]cstring{ "FZF_DEFAULT_OPTS=--bind ctrl-t:down,ctrl-s:up", nil }[0]));
    } else {
        res = intrinsics.syscall(unix.SYS_close, uintptr(pipefd[0]));
        input_data : string = strings.join(options, "\n")
        res = intrinsics.syscall(unix.SYS_write, uintptr(pipefd[1]), uintptr(raw_data(input_data)), uintptr(len(input_data)));
        res = intrinsics.syscall(unix.SYS_close, uintptr(pipefd[1]));

        res = intrinsics.syscall(unix.SYS_close, uintptr(backpipefd[1]));
        buf : [256]u8 = ---
        
        for bytes_read := intrinsics.syscall(unix.SYS_read, uintptr(backpipefd[0]), uintptr(&buf), uintptr(len(buf))) ; bytes_read > 0 ; bytes_read = intrinsics.syscall(unix.SYS_read, uintptr(backpipefd[0]), uintptr(&buf), uintptr(len(buf))) {
            //fmt.println("RECEIVED ", buf[:bytes_read])
            option_selected = strings.join([]string {option_selected, strings.clone_from(buf[:bytes_read])}, "")
        }
        res = intrinsics.syscall(unix.SYS_close, uintptr(backpipefd[0]));
        res = intrinsics.syscall(unix.SYS_wait4, uintptr(p), 0, 0, 0);
    }
    return strings.trim(option_selected, "\n")
}

main :: proc() {
    if len(os.args) < 2 {
        fmt.println("error: not enough arguments")
        return
    }

    data, success := os.read_entire_file(os.args[1])
    if !success {
        fmt.println("error: unable to read file")
        return
    }

    value, err := json.parse(data)
    if err != nil {
        fmt.println("error: unable to parse json")
        return
    }

    paths: [dynamic]string
    for k, _ in value.(json.Object)["paths"].(json.Object) {
        append(&paths, k)
    }

    path_to_look := make(map[string]bool)
    path_to_look["get"] = true
    path_to_look["post"] = true
    path_to_look["patch"] = true
    path_to_look["put"] = true
    path_to_look["trace"] = true
    path_to_look["head"] = true
    path_to_look["options"] = true

    path := fzf(paths[:]) 
    path_item_object := value.(json.Object)["paths"].(json.Object)[path].(json.Object)
    items: [dynamic]string
    for k, v in path_item_object {
        if k in path_to_look {
            append(&items, k)
        }
    }
    assert(len(items) > 0)
    item: string = ---
    if len(items) == 1 {
        item = items[0]
    }
    else {
        item = fzf(items[:])
    }
    fmt.println(item, path_item_object[item])
}
