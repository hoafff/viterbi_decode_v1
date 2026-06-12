# RTL V1 — Further optimized Viterbi decoder (K=3, R=1/2)

Thư mục này chứa phiên bản **rtl_v1** của RTL Viterbi decoder, phát triển tiếp từ `../rtl_p5/` (P5 hybrid) bằng cách thêm 2 cải tiến có hiệu quả cao:

1. **Precompute BMU_b (P3 reduced):** 8-FF bank latches `bm_b*` outputs ở phase A để ACS_odd ở phase B có input ổn định. BMU_b chỉ chạy ở phase A (active_a) → 0 dynamic power lãng phí ở phase B.
2. **Pipelined traceback (P-TB):** 3-stage pipeline thay cho 7-mức combinational traceback.

## Cấu trúc file

```
rtl_v1/
├── viterbi_decoder_v1.v       # Top-level
├── control_v1.v               # FSM 13 states (10 ACS + 3 traceback)
├── memory_v1.v                # Bank FF (mapping giống P5 đã sửa)
├── acs_pipeline_v1.v          # Wrapper: ACS_even (acs_csms) + pipereg + ACS_odd (acs_csms)
├── acs_csms.v                 # COPY từ rtl_p5 (dùng cho cả 2 ACS)
├── precompute_bmu.v           # MỚI: 8-FF lưu bm_b* outputs (chỉ ở phase A)
├── branch_metric_v1.v         # Tương tự branch_metric_p5
├── extract_bit_v1.v           # Tương tự extract_bit_p5
├── traceback_pipelined.v      # MỚI: 3-stage traceback pipeline
├── traceback.v                # COPY từ rtl_p5 (tham chiếu)
└── tb_viterbi_v1.v            # Testbench
```

## Khác biệt chính so với P5

| Khía cạnh | P5 | rtl_v1 |
|---|---|---|
| FSM states | 10 | **13** (thêm 3 state cho traceback) |
| Latency en → o_done | 7 cycles | **9 cycles** |
| ACS_even structure | acs_csms | acs_csms (giống P5) |
| BMU_b output cho ACS_odd | combo (gate ở phase B) | **8 FF precompute** (P3) |
| BMU_b active | gated bởi active_a | **gated bởi active_a** (giống P5 — tiết kiệm power) |
| Traceback | 7-mức combo | **3-stage pipeline** (P-TB) |
| Fmax ước lượng (sau layout, ss) | ~400 MHz | **~500-700 MHz** |
| ΔCell count vs baseline | +28% | **~+18-20%** (cell count) |
| ΔArea (sau routing) | +28% | **+25-30%** |

## Cách dùng

### Mô phỏng chức năng (iverilog)

```bash
cd "D:/NHÓM-6-final/2.viterbi code +setup/rtl_v1"
iverilog -g2012 -o tb_v1.vvp \
    viterbi_decoder_v1.v \
    control_v1.v memory_v1.v \
    acs_pipeline_v1.v acs_csms.v \
    precompute_bmu.v branch_metric_v1.v extract_bit_v1.v \
    traceback_pipelined.v \
    tb_viterbi_v1.v
vvp tb_v1.vvp
```

**Lưu ý đường dẫn:** testbench dùng `$readmemb("../Viterbi_input_error.txt", ...)`, vậy phải chạy từ `rtl_v1/`.

### Synthesis (Cadence Genus)

```tcl
cd rtl_v1
read_hdl -sv \
    viterbi_decoder_v1.v \
    control_v1.v memory_v1.v \
    acs_pipeline_v1.v acs_csms.v \
    precompute_bmu.v branch_metric_v1.v extract_bit_v1.v \
    traceback_pipelined.v
elaborate viterbi_decoder_v1
# ... (timing constraints như rtl_p5)
```

## Tóm tắt tinh thần thiết kế

- **Không thay đổi thuật toán:** cùng metric Hamming, cùng saturate 2-bit, cùng terminator 00, cùng trật tự butterfly, cùng "ties select A".
- **Output `o_data` tương đương bit-for-bit baseline**, chỉ shift +3 cycle latency so với baseline (9 vs 6 cycles).
- **Fmax mục tiêu:** ≥ 480 MHz sau layout, corner ss_1.62_125. Có thể đẩy lên ~700-1000 MHz nếu bỏ pipelined traceback.
- **Trade-off chính:** area cell count tăng ~+18-20% so với baseline (chủ yếu do precompute_bmu 8 FF + pipereg_pm_mid 8 FF + dec_even_latched 4 FF + traceback pipeline 2 FF), latency +3 cycles.

## Rủi ro & dự phòng

- Nếu precompute_bmu gây hold violation ở ff corner → tăng buffer delay trong layout.
- Nếu traceback 3-stage vẫn là critical path → có thể thêm 1 stage nữa (latency +4 cycles) để giảm xuống 3-mức logic.
- Nếu Fmax target > 700 MHz → bỏ `precompute_bmu` và `pipereg_pm_mid` (tiết kiệm 16 FF), dùng combo ACS (baseline 6 cycles latency) thay vì 2-stage ACS.
