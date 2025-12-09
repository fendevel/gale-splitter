package gale

import "core:log"
import "base:runtime"
import "core:mem"
import "core:bytes"
import "core:strconv"
import "core:slice"
import "core:time"
import "core:strings"
import "core:compress/zlib"
import "core:encoding/xml"

FrameDisposal :: enum {
	Unspecified = 0,
	NotDisposed = 1,
	BackgroundColor = 2,
	RestorePrevious = 3,
}

Header :: struct {
	sig: [8]byte,
	compressed_xml_length: u32,
}

Layer :: struct {
	left: int,
	top: int,
	visible: bool,
	trans_color: int,
	alpha: u8,
	alpha_on: bool,
	name: string,
	lock: bool,

    data: []byte `fmt:"-"`,
}

Milliseconds :: distinct int

Frame :: struct {
	name: string,
	trans_color: int,
	delay: time.Duration,
	disposal: FrameDisposal,

    width: int,
	height: int,
	bpp: int,

    palette: [][3]u8,
	layers: []Layer,
}

Gale :: struct {
	version: int,
	width: int,
	height: int,
	bpp: int,
	sync_pal: bool,
	randomized: bool,
	comp_type: int,
	comp_level: int,
	bg_color: u32,
	block_width: int,
	block_height: int,
	not_fill_bg: int,

	frames: []Frame,
}

parse_buffer :: proc(buffer: []byte, allocator := context.temp_allocator) -> (gale: Gale, good: bool) {
	header: Header = mem.reinterpret_copy(Header, &buffer[0])

	if string(header.sig[:]) != "GaleX200"	{
        return {}, false
	}

    compressed_xml := buffer[size_of(Header):][:header.compressed_xml_length]

    xml_decompbuff: bytes.Buffer
    bytes.buffer_init_allocator(&xml_decompbuff, 0, mem.Kilobyte*0x10, context.temp_allocator)
    zlib.inflate_from_byte_array(compressed_xml, &xml_decompbuff, false)

    doc: ^xml.Document = xml.parse_bytes(xml_decompbuff.buf[:]) or_else panic("???")

    log.debug(string(doc.input))

    if val, has_val := xml.find_attribute_val_by_key(doc, 0, "Version"); has_val {
        gale.version = strconv.parse_int(val) or_else panic("???")
    }

    if val, has_val := xml.find_attribute_val_by_key(doc, 0, "Width"); has_val {
        gale.width = strconv.parse_int(val) or_else panic("???")
    }

    if val, has_val := xml.find_attribute_val_by_key(doc, 0, "Height"); has_val {
        gale.height = strconv.parse_int(val) or_else panic("???")
    }

    if val, has_val := xml.find_attribute_val_by_key(doc, 0, "Bpp"); has_val {
        gale.bpp = strconv.parse_int(val) or_else panic("???")
    }

    if val, has_val := xml.find_attribute_val_by_key(doc, 0, "Count"); has_val {
        count := strconv.parse_int(val) or_else panic("???")
        gale.frames = make([]Frame, count, allocator)
    }

    if val, has_val := xml.find_attribute_val_by_key(doc, 0, "SyncPal"); has_val {
        gale.sync_pal = strings.has_prefix(val, "1")
    }

    if val, has_val := xml.find_attribute_val_by_key(doc, 0, "Randomized"); has_val {
        gale.randomized = strings.has_prefix(val, "1")
    }

    if val, has_val := xml.find_attribute_val_by_key(doc, 0, "CompType"); has_val {
        gale.comp_type = strconv.parse_int(val) or_else panic("???")
    }

    if val, has_val := xml.find_attribute_val_by_key(doc, 0, "CompLevel"); has_val {
        gale.comp_level = strconv.parse_int(val) or_else panic("???")
    }

    if val, has_val := xml.find_attribute_val_by_key(doc, 0, "BGColor"); has_val {
        val := strconv.parse_uint(val) or_else panic("???")
        gale.bg_color = u32(val)
    }

    if val, has_val := xml.find_attribute_val_by_key(doc, 0, "BlockWidth"); has_val {
        gale.block_width = strconv.parse_int(val) or_else panic("???")
    }

    if val, has_val := xml.find_attribute_val_by_key(doc, 0, "BlockHeight"); has_val {
        gale.block_height = strconv.parse_int(val) or_else panic("???")
    }

    if val, has_val := xml.find_attribute_val_by_key(doc, 0, "NotFillBG"); has_val {
        gale.not_fill_bg = strconv.parse_int(val) or_else panic("???")
    }

    for &frame, j in gale.frames {
        frame_id := xml.find_child_by_ident(doc, 0, "Frame", j) or_else panic("???")

        if val, has_val := xml.find_attribute_val_by_key(doc, frame_id, "Name"); has_val {
            frame.name = val
        }

        if val, has_val := xml.find_attribute_val_by_key(doc, frame_id, "TransColor"); has_val {
            val := strconv.parse_int(val) or_else panic("???")
            frame.trans_color = val
        }

        if val, has_val := xml.find_attribute_val_by_key(doc, frame_id, "Delay"); has_val {
            val := strconv.parse_int(val) or_else panic("???")
            frame.delay = time.Millisecond*time.Duration(val)
        }

        if val, has_val := xml.find_attribute_val_by_key(doc, frame_id, "Disposal"); has_val {
            val := strconv.parse_int(val) or_else panic("???")
            frame.disposal = FrameDisposal(val)
        }

        layers_id := xml.find_child_by_ident(doc, frame_id, "Layers") or_else panic("???")

        if val, has_val := xml.find_attribute_val_by_key(doc, layers_id, "Count"); has_val {
            val := strconv.parse_int(val) or_else panic("???")
            frame.layers = make([]Layer, val, allocator)
        }

        if val, has_val := xml.find_attribute_val_by_key(doc, layers_id, "Width"); has_val {
            frame.width = strconv.parse_int(val) or_else panic("???")
        }

        if val, has_val := xml.find_attribute_val_by_key(doc, layers_id, "Height"); has_val {
            frame.height = strconv.parse_int(val) or_else panic("???")
        }

        if val, has_val := xml.find_attribute_val_by_key(doc, layers_id, "Bpp"); has_val {
            frame.bpp = strconv.parse_int(val) or_else panic("???")
        }

        if palette_id, has_palette := xml.find_child_by_ident(doc, layers_id, "RGB"); has_palette {
            assert(frame.bpp <= 8)
            frame.palette = make([][3]u8, 1 << uint(frame.bpp))
            palette := doc.elements[palette_id].value[0].(string) or_else panic("???")

            palette_size := 1 << uint(gale.bpp)
        
            for p in 0..<palette_size {
                rgb: uint = strconv.parse_uint(palette[p*6:][:6], 0x10) or_else panic("???")
                frame.palette[p] = mem.reinterpret_copy([3]u8, &rgb)
            }
        }

        for &layer, i in frame.layers {
            layer_id := xml.find_child_by_ident(doc, layers_id, "Layer", i) or_else panic("???")

            if val, has_val := xml.find_attribute_val_by_key(doc, layer_id, "Left"); has_val {
                layer.left = strconv.parse_int(val) or_else panic("???")
            }

            if val, has_val := xml.find_attribute_val_by_key(doc, layer_id, "Top"); has_val {
                layer.top = strconv.parse_int(val) or_else panic("???")
            }

            if val, has_val := xml.find_attribute_val_by_key(doc, layer_id, "Visible"); has_val {
                layer.visible = strings.has_prefix(val, "1")
            }

            if val, has_val := xml.find_attribute_val_by_key(doc, layer_id, "TransColor"); has_val {
                val := strconv.parse_int(val) or_else panic("???")
                layer.trans_color = val
            }

            if val, has_val := xml.find_attribute_val_by_key(doc, layer_id, "Alpha"); has_val {
                val := strconv.parse_int(val) or_else panic("???")
                layer.alpha = u8(val)
            }

            if val, has_val := xml.find_attribute_val_by_key(doc, layer_id, "AlphaOn"); has_val {
                layer.alpha_on = strings.has_prefix(val, "1")
            }

            if val, has_val := xml.find_attribute_val_by_key(doc, layer_id, "Name"); has_val {
                layer.name = val
            }

            if val, has_val := xml.find_attribute_val_by_key(doc, layer_id, "Lock"); has_val {
                layer.lock = strings.has_prefix(val, "1")
            }
        }
    }

    offset := size_of(Header) + header.compressed_xml_length
    block_index := 0

    buff: bytes.Buffer
    bytes.buffer_init_allocator(&buff, 0, mem.Megabyte*0x10, context.temp_allocator)

    for &frame in gale.frames {
        for &layer in frame.layers {
            defer bytes.buffer_reset(&buff)

            compressed_size := mem.reinterpret_copy(u32, &buffer[offset])
            offset += 4

            src_len := compressed_size
            zlib.inflate_from_byte_array(buffer[offset:][:compressed_size], &buff)

            layer.data = slice.clone(buff.buf[:], allocator)

            offset += src_len + 4
            block_index += 1
        }
    }

    good = true

    return
}