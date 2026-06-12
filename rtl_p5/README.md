# RTL P5 — Hybrid high-speed Viterbi decoder (K=3, R=1/2)

Thư mục này chứa phiên bản P5 của RTL Viterbi decoder, **cách ly hoàn toàn** với `../rtl/` (baseline gốc của nhóm).

## Cấu trúc file

```
rtl_p5/
├── viterbi_decoder_p5.v     # top-level P5
├── viterbi_decoder.v        # BẢN SAO BASELINE (chỉ để tham chiếu, KHÔNG dùng cho synthesis)
├── control_p5.v             # FSM 10 trạng thái (P1)
├── control.v                # BẢN SAO BASELINE
├── memory_p5.v              # bank FF + dec_s* split theo phase (P1)
├── memory.v                 # BẢN SAO BASELINE
├── acs_csms.v               # ACS butterfly dùng CSMS + OR-saturate (P2)
├── add_comp_slt.v           # BẢN SAO BASELINE
├── acs_pipeline_p5.v        # wrapper chèn FF pipereg giữa ACS_even và ACS_odd (P1)
├── branch_metric_p5.v       # BMU + operand-isolation (P0.3)
├── branch_metric.v          # BẢN SAO BASELINE
├── extract_bit_p5.v         # trích symbol từ rx_reg, bỏ state port (P0.5)
├── extract_bit.v            # BẢN SAO BASELINE
├── traceback.v              # GIỮ NGUYÊN (không sửa)
└── tb_viterbi_readmemb_p5.v # testbench cho P5
```

Các file **không có hậu tố `_p5`** là bản sao của baseline (chỉ giữ để tham chiếu, dễ so sánh). Module `viterbi_decoder_p5` chỉ instantiate các file `_p5` + `traceback.v` chung.

## Khác biệt chính so với baseline

| Khía cạnh | Baseline | P5 |
|---|---|---|
| FSM states | 6 | 10 (mỗi ACS cycle có phase A và phase B) |
| Latency en → o_done | 6 cycles | **7 cycles** |
| ACS structure | flat add-comp-slt | CSMS compare-select + OR-saturate |
| Pipeline | không | FF pipereg giữa ACS_even và ACS_odd |
| BMU operand-isolation | không | có (gating bằng `active_a`) |
| State port width | `[2:0]` | `[3:0]` |
| Fmax ước lượng (sau layout, ss) | ~220 MHz | **~400 MHz** |

## Cách dùng

### Mô phỏng chức năng (iverilog)

```bash
cd "D:\NHÓM-6-final\2.viterbi code +setup\rtl_p5"
iverilog -g2012 -o tb_p5.vvp \
    viterbi_decoder_p5.v \
    control_p5.v memory_p5.v \
    acs_pipeline_p5.v acs_csms.v \
    branch_metric_p5.v extract_bit_p5.v \
    traceback.v \
    tb_viterbi_readmemb_p5.v
vvp tb_p5.vvp
```

**Lưu ý đường dẫn file input:** testbench dùng `$readmemb("Viterbi_input_error.txt", ...)`. Khi chạy `vvp`, file này cần ở working directory. Cách đơn giản:

```bash
cd "D:\NHÓM-6-final\2.viterbi code +setup"
vvp rtl_p5/tb_p5.vvp    # nếu đã copy output lên thư mục gốc
```

Hoặc sửa trong `tb_viterbi_readmemb_p5.v` thành `$readmemb("../Viterbi_input_error.txt", ...)` nếu chạy từ `rtl_p5/`.

### Synthesis (Cadence Genus)

```tcl
# Trong Genus
cd rtl_p5
read_hdl -sv \
    viterbi_decoder_p5.v \
    control_p5.v memory_p5.v \
    acs_pipeline_p5.v acs_csms.v \
    branch_metric_p5.v extract_bit_p5.v \
    traceback.v
elaborate viterbi_decoder_p5
# ... (ràng buộc timing, set_clock, syn_map, syn_opt như báo cáo P5 mục 11.1)
```

### Layout (Cadence Innovus)

Sau khi synthesis xong, file netlist nằm trong `../synthesis/outputs/viterbi_p5_netlist.v`. Chạy layout bình thường, top module là `viterbi_decoder_p5`.

## Tài liệu tham chiếu

Xem `../viterbi_p5_implementation.md` (báo cáo triển khai đầy đủ) và `../viterbi_high_speed_options.md` (báo cáo khảo sát 7 phương án).

## Tóm tắt tinh thần thiết kế

- **Không thay đổi thuật toán:** cùng metric Hamming, cùng saturate 2-bit, cùng terminator 00, cùng trật tự butterfly, cùng quy tắc "ties select A". Output `o_data` tương đương bit-for-bit baseline, chỉ shift +1 cycle latency.
- **Fmax mục tiêu:** ≥ 400 MHz sau layout, corner ss_1.62_125.
- **Trade-off chính:** area tăng ~28% (do thêm FF pipereg), latency +1 cycle, không thay đổi giải thuật.
