package gsplitter

import "core:slice"
import "core:mem"
import "core:strings"
import "core:terminal/ansi"
import "core:path/filepath"
import "core:fmt"
import "core:os/os2"

import "vendor:stb/image"

import "gale"

VERSION_MAJOR :: 1
VERSION_MINOR :: 4

ERROR :: ansi.CSI + ansi.FG_RED + ansi.SGR + "error" + ansi.CSI + ansi.RESET + ansi.SGR
SUCCESS :: ansi.CSI + ansi.FG_GREEN + ansi.SGR + "success" + ansi.CSI + ansi.RESET + ansi.SGR
SKIP :: ansi.CSI + ansi.FG_YELLOW + ansi.SGR + "skip" + ansi.CSI + ansi.RESET + ansi.SGR

RGB565 :: bit_field u16 {
    r: u8 | 5,
    g: u8 | 6,
    b: u8 | 5,
}

RGB555 :: bit_field u16 {
    r: u8 | 5,
    g: u8 | 5,
    b: u8 | 5,
}

colstr :: proc(str: string, col: string, allocator := context.temp_allocator) -> string {
    return fmt.aprintf(ansi.CSI + "{}" + ansi.SGR + "{}" + ansi.CSI + ansi.RESET + ansi.SGR, col, str, allocator = allocator)
}

// Jerry R. Van Aken: https://arxiv.org/pdf/2202.02864
fast_alpha_mult :: proc(alpha: u8, red: u8) -> u8 {
    red := u32(red)*u32(alpha)
    red += 0x80
    red += red >> 8
    return u8(red >> 8)
}

main :: proc () {
    show_help := true

    noclip := false
    noskip := false

    for arg in os2.args {
        if strings.starts_with(arg, "-") {
            if slice.contains([]string{"-v", "--version" }, arg) {
                fmt.printfln("gale-splitter version {}.{}", VERSION_MAJOR, VERSION_MINOR)
                show_help = false
            } else if slice.contains([]string{ "-h", "--help" }, arg) {
                show_help = true
            } else if arg == "--noclip" {
                noclip = true
            } else if arg == "--noskip" {
                noskip = true
            } else {
                fmt.printfln("{}: unrecognised option \"{}\"", ERROR, arg)
                os2.exit(1)
            }
        }
    }

    for arg in os2.args {
        if filepath.ext(arg) != ".gal" {
            continue
        }

        show_help = false
        
        if !os2.exists(arg) {
            fmt.printfln("{}: failed to find file {}", ERROR, arg)
            os2.exit(1)
        }

        buffer, err := os2.read_entire_file(arg, context.temp_allocator)
        if err != nil {
            fmt.printfln("{}: failed to open file {}", ERROR, arg)
            fmt.printfln("error code: {}", err)
            os2.exit(1)
        }

        file, error := gale.parse_buffer(buffer)
        if error != .Success {
            fmt.printfln("{}: failed to parse file {} with code: {}", ERROR, arg, error)
            os2.exit(1)
        }

        fmt.printfln("current file: {}", arg)

        out_dir := strings.trim_suffix(arg, ".gal")
        if !os2.exists(out_dir) {
            os2.make_directory(out_dir)
        }

        dst_w := int(file.width)
        dst_h := int(file.height)
        dst_pitch := dst_w*size_of([4]byte)
        dst_data := make([][4]byte, dst_w*dst_h, context.temp_allocator)

        for frame, j in file.frames {
            src_w := int(frame.width)
            src_h := int(frame.height)

            frame_tcol := frame.trans_color

            frame_counter := j + 1

            for layer, i in frame.layers {
                layer_counter := i + 1

                out_path := fmt.ctprintf("{}/f{}_{}.png", out_dir, j, layer.name)
                status: i32

                slice.zero(dst_data)

                minaabb: [2]int = max(int)
                maxaabb: [2]int = min(int)

                layer_tcol := layer.trans_color

                src_pitch := len(layer.data) / src_h
                src_alpha_pitch := len(layer.data_alpha) / src_h

                switch frame.bpp {
                    case 24: {
                        for y in 0..<src_h {
                            for x in 0..<src_w {
                                src: u32
                                mem.copy(&src, &layer.data[y*src_pitch + x*3], 3)
                                col: [4]byte
                                if int(src) != layer_tcol && int(src) != frame_tcol {
                                    col.bgr = (transmute([4]byte)src).rgb
                                    col.a = layer.alpha

                                    minaabb.x = min(minaabb.x, x)
                                    minaabb.y = min(minaabb.y, y)
                                    
                                    maxaabb.x = max(maxaabb.x, x + 1)
                                    maxaabb.y = max(maxaabb.y, y + 1)
                                }

                                if layer.alpha_on {
                                    col.a = fast_alpha_mult(layer.alpha, layer.data_alpha[y*src_alpha_pitch + x])
                                }

                                dst_data[y*dst_w + x] = col
                            }
                        }
                    }
                    case 16: {
                        for y in 0..<src_h {
                            for x in 0..<src_w {
                                src: u16
                                mem.copy(&src, &layer.data[y*src_pitch + x*2], 2)
                                col: [4]byte
                                if int(src) != layer_tcol && int(src) != frame_tcol {
                                    rgb := transmute(RGB565)src
                                    col.b = u8(((u32(rgb.r) + 1) << 3) - 1)
                                    col.g = u8(((u32(rgb.g) + 1) << 2) - 1)
                                    col.r = u8(((u32(rgb.b) + 1) << 3) - 1)
                                    
                                    col.a = layer.alpha

                                    minaabb.x = min(minaabb.x, x)
                                    minaabb.y = min(minaabb.y, y)
                                    
                                    maxaabb.x = max(maxaabb.x, x + 1)
                                    maxaabb.y = max(maxaabb.y, y + 1)
                                }

                                if layer.alpha_on {
                                    col.a = fast_alpha_mult(layer.alpha, layer.data_alpha[y*src_alpha_pitch + x])
                                }

                                dst_data[y*dst_w + x] = col
                            }
                        }
                    }
                    case 15: {
                        for y in 0..<src_h {
                            for x in 0..<src_w {
                                src: u16
                                mem.copy(&src, &layer.data[y*src_pitch + x*2], 2)
                                col: [4]byte
                                if int(src) != layer_tcol && int(src) != frame_tcol {
                                    rgb := transmute(RGB555)src
                                    col.b = u8(((u32(rgb.r) + 1) << 3) - 1)
                                    col.g = u8(((u32(rgb.g) + 1) << 3) - 1)
                                    col.r = u8(((u32(rgb.b) + 1) << 3) - 1)
                                    
                                    col.a = layer.alpha

                                    minaabb.x = min(minaabb.x, x)
                                    minaabb.y = min(minaabb.y, y)
                                    
                                    maxaabb.x = max(maxaabb.x, x + 1)
                                    maxaabb.y = max(maxaabb.y, y + 1)
                                }

                                if layer.alpha_on {
                                    col.a = fast_alpha_mult(layer.alpha, layer.data_alpha[y*src_alpha_pitch + x])
                                }

                                dst_data[y*dst_w + x] = col
                            }
                        }
                    }
                    case 8: {
                        for y in 0..<src_h {
                            for x in 0..<src_w {
                                src_index := layer.data[y*src_pitch + x]
                                col: [4]byte

                                if int(src_index) != layer_tcol && int(src_index) != frame_tcol {
                                    col.rgb = frame.palette[src_index]
                                    col.a = layer.alpha

                                    minaabb.x = min(minaabb.x, x)
                                    minaabb.y = min(minaabb.y, y)
                                    
                                    maxaabb.x = max(maxaabb.x, x + 1)
                                    maxaabb.y = max(maxaabb.y, y + 1)
                                }

                                if layer.alpha_on {
                                    col.a = fast_alpha_mult(layer.alpha, layer.data_alpha[y*src_alpha_pitch + x])
                                }

                                dst_data[y*dst_w + x] = col
                            }
                        }
                    }
                    case 4: {
                        for y in 0..<src_h {
                            for x in 0..<src_w {
                                src_index := (layer.data[y*src_pitch + x/2] >> (u8(1 - (x % 2))*4)) & 0xf
                                col: [4]byte

                                if int(src_index) != layer_tcol && int(src_index) != frame_tcol {
                                    col.rgb = frame.palette[src_index]
                                    col.a = layer.alpha

                                    minaabb.x = min(minaabb.x, x)
                                    minaabb.y = min(minaabb.y, y)
                                    
                                    maxaabb.x = max(maxaabb.x, x + 1)
                                    maxaabb.y = max(maxaabb.y, y + 1)
                                }

                                if layer.alpha_on {
                                    col.a = fast_alpha_mult(layer.alpha, layer.data_alpha[y*src_alpha_pitch + x])
                                }

                                dst_data[y*dst_w + x] = col
                            }
                        }
                    }
                    case 1: {
                        for y in 0..<src_h {
                            for x in 0..<src_w {
                                src_index := (layer.data[y*src_pitch + x/8] >> (u8(7 - (x % 8)))) & 1
                                col: [4]byte

                                if int(src_index) != layer_tcol && int(src_index) != frame_tcol {
                                    col.rgb = frame.palette[src_index]
                                    col.a = layer.alpha

                                    minaabb.x = min(minaabb.x, x)
                                    minaabb.y = min(minaabb.y, y)
                                    
                                    maxaabb.x = max(maxaabb.x, x + 1)
                                    maxaabb.y = max(maxaabb.y, y + 1)
                                }

                                if layer.alpha_on {
                                    col.a = fast_alpha_mult(layer.alpha, layer.data_alpha[y*src_alpha_pitch + x])
                                }

                                dst_data[y*dst_w + x] = col
                            }
                        }
                    }
                }

                if !noskip && (minaabb == max(int) && maxaabb == min(int)) {
                    fmt.printfln("   {}: layer {}{}{}{}{} of frame {}{}{}{}{} \"{}\" is empty", SKIP, 
                        colstr("[", ansi.FG_BRIGHT_BLACK), colstr(fmt.tprintf("{: 2d}", layer_counter), ansi.FG_CYAN), colstr("/", ansi.FG_BRIGHT_BLACK), colstr(fmt.tprintf("{: 2d}", len(frame.layers)), ansi.FG_CYAN), colstr("]", ansi.FG_BRIGHT_BLACK), 
                        colstr("[", ansi.FG_BRIGHT_BLACK), colstr(fmt.tprintf("{: 2d}", frame_counter), ansi.FG_CYAN), colstr("/", ansi.FG_BRIGHT_BLACK), colstr(fmt.tprintf("{: 2d}", len(file.frames)), ansi.FG_CYAN), colstr("]", ansi.FG_BRIGHT_BLACK),
                        layer.name)
                    continue
                }

                final_w := (maxaabb.x - minaabb.x) if !noclip else frame.width
                final_h := (maxaabb.y - minaabb.y) if !noclip else frame.height
                dst_ptr := &dst_data[(minaabb.y*dst_w + minaabb.x) if !noclip else 0]

                status = image.write_png(out_path, i32(final_w), i32(final_h), 4, dst_ptr, i32(dst_pitch))

                if status != 1 {
                    fmt.printfln(" {}: layer {}{}{}{}{} of frame {}{}{}{}{} \"{}\": {}", ERROR, 
                        colstr("[", ansi.FG_BRIGHT_BLACK), colstr(fmt.tprintf("{: 2d}", layer_counter), ansi.FG_RED), colstr("/", ansi.FG_BRIGHT_BLACK), colstr(fmt.tprintf("{: 2d}", len(frame.layers)), ansi.FG_CYAN), colstr("]", ansi.FG_BRIGHT_BLACK), 
                        colstr("[", ansi.FG_BRIGHT_BLACK), colstr(fmt.tprintf("{: 2d}", frame_counter), ansi.FG_RED), colstr("/", ansi.FG_BRIGHT_BLACK), colstr(fmt.tprintf("{: 2d}", len(file.frames)), ansi.FG_CYAN), colstr("]", ansi.FG_BRIGHT_BLACK),
                        layer.name, "unknown error writing output file")
                    continue
                }
                
                fmt.printfln("{}: layer {}{}{}{}{} of frame {}{}{}{}{} \"{}\" -> {}", SUCCESS, 
                    colstr("[", ansi.FG_BRIGHT_BLACK), colstr(fmt.tprintf("{: 2d}", layer_counter), ansi.FG_CYAN), colstr("/", ansi.FG_BRIGHT_BLACK), colstr(fmt.tprintf("{: 2d}", len(frame.layers)), ansi.FG_CYAN), colstr("]", ansi.FG_BRIGHT_BLACK), 
                    colstr("[", ansi.FG_BRIGHT_BLACK), colstr(fmt.tprintf("{: 2d}", frame_counter), ansi.FG_CYAN), colstr("/", ansi.FG_BRIGHT_BLACK), colstr(fmt.tprintf("{: 2d}", len(file.frames)), ansi.FG_CYAN), colstr("]", ansi.FG_BRIGHT_BLACK),
                    layer.name, out_path)
            }
        }
    }

    if show_help {
        fmt.printfln("USAGE:")
        
        fmt.printfln("       gale-splitter -h|--help")
        fmt.printfln("       \tdisplays this message")
        fmt.println()
        
        fmt.printfln("       gale-splitter -v|--version")
        fmt.printfln("       \tprints the version number")
        fmt.println()
        
        fmt.printfln("       gale-splitter --noclip")
        fmt.printfln("       \tpreserves original frame size")
        fmt.println()

        fmt.printfln("       gale-splitter --noskip")
        fmt.printfln("       \twon't skip empty layers")
        fmt.println()
        
        fmt.printfln("EXAMPLE:")
        fmt.printfln("       gale-splitter file0.gal file1.gal file2.gal")
    }
}