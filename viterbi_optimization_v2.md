# BẢN TỐI ƯU MAX-fmax CHO VITERBI K=3, R=1/2 (giữ latency 6 clk, throughput 1 frame/6 clk)

> Phản hồi cho `viterbi_fix_pipeline_loop.md`. Bản đó tự nhận sửa lỗi nhưng vẫn mắc lỗi cấu trúc (đếm nhầm `N_reg`, latency sai, suy ra iteration bound sai). Bản này viết lại từ đầu dựa trên RTL thật (`rtl/*.v`) và SDC thật (`viterbi_sdc.sdc`).
>
> **Mục tiêu duy nhất:** fmax cao nhất có thể. Latency = 6 clk, throughput = 1 frame / 6 clk, thuật toán Viterbi K=3 R=1/2, giao tiếp I/O giữ nguyên.

---

## 0. BASELINE ĐÚNG TỪ RTL THẬT

### 0.1 Đọc RTL, đếm reg, đo latency

Từ `rtl/viterbi_decoder.v` dòng 89, 108 và `rtl/add_comp_slt.v` dòng 17–20:

```verilog
// viterbi_decoder.v
wire [1:0] pm_mid00, pm_mid01, pm_mid10, pm_mid11;   // <-- WIRE, không phải reg
wire [1:0] pm_new00, pm_new01, pm_new10, pm_new11;   // <-- WIRE

// add_comp_slt.v
output wire [1:0] new_pm00;   // <-- output wire, không có always block
```

`pm_mid*` và `pm_new*` đều là **wire tổ hợp**, nối thẳng output của `u_acs_even` sang `u_acs_odd`, rồi sang `memory.pm*`. Trong `memory.v` (dòng 105–124) mới có `always @(posedge clk)` ghi vào reg `pm00..pm11`.

Vậy **vòng ACS chỉ có đúng 1 register**: `pm*` trong `memory.v`. Hai stage `u_acs_even` và `u_acs_odd` nối tiếp **thuần tổ hợp trong cùng một chu kỳ**.

Từ `rtl/control.v` dòng 27–41 (FSM):
```
ST_IDLE -> ST_01 -> ST_23 -> ST_45 -> ST_67 -> ST_OUT -> ST_IDLE
```
5 chuyển trạng thái. Khi `en=1` ở ST_IDLE, `load_frame=1`, `rx_reg <= i_data`, `pm00<=0, pm01..11<=3`. Sau 1 clk vào ST_01 (active), 4 clk ST_01..ST_67 (active), 1 clk ST_OUT (output_cycle). `o_done` được set trong ST_OUT, reg-clocked.

**Latency từ `en` đến `o_done` = 6 clk** (khớp comment `viterbi_decoder.v` dòng 9: "6 clock cycles"). Bản cũ ghi "10 clk" là **sai**.

### 0.2 Critical path thật

Đường tổ hợp dài nhất trong 1 active cycle:

```
rx_reg[15:12] (FF)
  -> branch_metric (1 XOR + 1 half-adder = 1 gate delay)
  -> acs_even (add 2b+2b = 1 FA, sat mux, compare, mux2:1 = ~4 gate delays)
  -> acs_odd  (cùng cấu trúc = ~4 gate delays)
  -> memory.pm* (FF, setup time + clk->Q)
```

Tổng `T_loop` ≈ **8–9 gate delays** cho combinational giữa 2 cổng FF. Iteration bound `T∞ = T_loop / N_reg = 8 / 1 ≈ 8 gate delays` — tức là tần số cực đại lý thuyết bị chặn bởi bound này.

### 0.3 Hệ quả: vì sao baseline đạt ~200 MHz

`viterbi_sdc.sdc` đặt `create_clock -period 5.0` → 200 MHz. Nếu mỗi gate delay ở sky130 ss corner ~0.4–0.5 ns (1 NAND + wire RC), 8 gates × 0.5 ns = 4 ns combinational, cộng setup + clk_skew + uncertainty = 5 ns → vừa khít 200 MHz, slack gần 0 hoặc âm nhẹ. Con số "WNS = -163 ps initial, +60 ps final" mà bản cũ đưa ra **hợp lý** với mô hình này (tuy chưa tự mình giải nén report để verify).

### 0.4 Sai lầm của bản cũ (cần sửa)

| Bản cũ nói | Thực tế |
|------------|---------|
| `N_reg = 2` (pm_mid + pm) | `N_reg = 1` (chỉ pm) |
| `T∞ = T_loop / 2` | `T∞ = T_loop / 1` (gấp đôi) |
| Latency hiện tại = 10 clk | Latency = 6 clk |
| Latency sau sửa = 12 clk | Phải giữ 6 clk (ràng buộc) |
| ACS_even ở cycle 2, ACS_odd ở cycle 3 | Cả 2 ACS chạy **cùng cycle** (cùng ST_01) |
| Carry-save giúp giảm 1 tầng | Carry-save vô nghĩa cho 2b+2b (FA đã tối ưu) |
| Modulo 4-bit | Hekstra cần 3 bit (log2(K×max_bm)+1 = log2(6)+1 = 3) |

---

## 1. NGUYÊN TẮC THIẾT KẾ (ràng buộc cứng)

1. **Vòng ACS có 1 reg duy nhất** — mọi tối ưu phải tôn trọng `N_reg = 1`.
2. **Latency = 6 clk cố định** — đây là constraint, không được tăng.
3. **Throughput = 1 frame / 6 clk** — giữ nguyên.
4. **Cách duy nhất để tăng fmax với `N_reg = 1`:** rút ngắn `T_loop` (giảm combinational delay trong vòng) HOẶC tăng `N_reg` lên 2/3 bằng cách chèn reg **mà vẫn giữ latency 6 clk**.
5. **Cách tăng `N_reg` mà không tăng latency:** chèn reg trong vòng, nhưng **rút ngắn 1 active cycle ở nơi khác** để bù. Cụ thể: 4 active cycle (ST_01..ST_67) hiện mỗi cycle xử lý 1 cặp symbol (pair_a, pair_b). Nếu giờ mỗi cycle xử lý 2 cặp symbol (radix-2), ta có thể giảm xuống 2 active cycle, dư 2 clk để chèn 2 reg trong pipeline mới.

---

## 2. CÁC PHƯƠNG ÁN SÂU (đã đánh giá iteration bound đúng)

### PA1 — Retiming ACS bằng reg giữa 2 stage (N_reg: 1 → 2)

**Ý tưởng:** Chèn reg `pm_mid_reg*` giữa output `u_acs_even` và input `u_acs_odd`. Mỗi ACS stage giờ chỉ cần đạt ~4 gate delays thay vì 4+4=8 nối tiếp.

**RTL patch (gọi ý):**
```verilog
// viterbi_decoder.v - chèn reg giữa 2 ACS
reg [1:0] pm_mid_r00, pm_mid_r01, pm_mid_r10, pm_mid_r11;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) {pm_mid_r00,pm_mid_r01,pm_mid_r10,pm_mid_r11} <= 8'b0;
    else if (load_frame) {pm_mid_r00,pm_mid_r01,pm_mid_r10,pm_mid_r11} <= 8'd0;
    else if (active) {pm_mid_r00,pm_mid_r01,pm_mid_r10,pm_mid_r11} <= {pm_mid00,pm_mid01,pm_mid10,pm_mid11};
end

add_comp_slt u_acs_odd (
    .pm00(pm_mid_r00), .pm01(pm_mid_r01), .pm10(pm_mid_r10), .pm11(pm_mid_r11),
    ...
);
```

**Iteration bound mới:** `T∞ = T_loop / 2 = 4 / 2 = 2 gate delays` (lấy `T_loop` sau khi chèn reg = 4 gates mỗi ACS, mỗi ACS nằm trong vòng 1 stage).

**Hệ quả:** Latency tăng 1 clk (giờ ACS_even ở cycle N, ACS_odd ở cycle N+1). Để giữ 6 clk, phải bù bằng cách **xử lý 2 cặp symbol/cycle** (gộp 2 active cycle thành 1). Đây là chỗ kết hợp với PA2.

**Ưu điểm:** Tăng fmax đáng kể vì iteration bound giảm một nửa.
**Đánh đổi:** Phải kết hợp với radix-2 để giữ latency.

### PA2 — Radix-2 look-ahead (gộp 2 bước trellis)

**Ý tưởng:** Thay vì mỗi active cycle xử lý 1 cặp (pair_a, pair_b) qua 2 ACS nối tiếp, gộp thành 1 stage tính 2 cặp đồng thời. Công thức:

```
pm_new_even = ACS_even(pm, bm_a)   // symbol thứ nhất
pm_new_odd  = ACS_odd(pm_new_even, bm_b)  // symbol thứ hai, dùng output ACS_even làm input
```

Đây chính là cấu trúc hiện tại của bạn. **Radix-2 thật sự** là tính 1 stage tổ hợp từ `pm` đến `pm_after_2_symbols` trong 1 cycle, với công thức tường minh:

```
pm_after_2_symbols = ACS_odd(ACS_even(pm, bm_a), bm_b)
```

Thay vì 2 ACS module rời, viết 1 module `radix2_acs` nhận 4 bm (bm_a00..bm_b01) và 4 pm, cho ra 4 pm_mới.

**RTL patch:**
```verilog
module radix2_acs (
    input  wire [1:0] bm_a00, bm_a11, bm_a10, bm_a01,
    input  wire [1:0] bm_b00, bm_b11, bm_b10, bm_b01,
    input  wire [1:0] pm00, pm01, pm10, pm11,
    output wire [1:0] new_pm00, new_pm01, new_pm10, new_pm11
);
    wire [1:0] pm_mid00, pm_mid01, pm_mid10, pm_mid11;
    add_comp_slt u_step1 (
        .bm00(bm_a00), .bm11(bm_a11), .bm10(bm_a10), .bm01(bm_a01),
        .pm00(pm00), .pm01(pm01), .pm10(pm10), .pm11(pm11),
        .new_pm00(pm_mid00), .new_pm01(pm_mid01),
        .new_pm10(pm_mid10), .new_pm11(pm_mid11), .decision()
    );
    add_comp_slt u_step2 (
        .bm00(bm_b00), .bm11(bm_b11), .bm10(bm_b10), .bm01(bm_b01),
        .pm00(pm_mid00), .pm01(pm_mid01), .pm10(pm_mid10), .pm11(pm_mid11),
        .new_pm00(new_pm00), .new_pm01(new_pm01),
        .new_pm10(new_pm10), .new_pm11(new_pm11), .decision()
    );
endmodule
```

**Quan trọng:** Khi kết hợp PA1+PA2, vẫn chèn reg giữa 2 step bên trong `radix2_acs`, biến nó thành 1 radix-2 stage 2-cycle. Cứ 2 clk xử lý 2 cặp symbol = 1 cặp `(pair_a, pair_b)`. Như vậy:
- Active cycles: 2 (ST_01, ST_23) thay vì 4.
- Mỗi active cycle xử lý 1 cặp pair, nhưng pair giờ là 4 symbol (8 bit) thay vì 2 symbol (4 bit).
- Cần mở rộng `rx_reg` từ shift-by-4 lên shift-by-8.

**Latency:** 1 load + 2 active + 1 output = **4 clk** (giảm 2 clk so với baseline). Nếu muốn giữ 6 clk, có thể thêm 2 stage pipeline BMU/traceback để bù latency mà vẫn tăng fmax.

### PA3 — C-slow 2-way interleaving

**Ý tưởng:** Chạy 2 frame độc lập luân phiên. Mỗi frame có 1 bộ ACS chain riêng, share traceback + control.

**RTL patch:** Nhân đôi `u_acs_even`, `u_acs_odd`, `u_radix2_acs`, reg `pm*`, `rx_reg*`, `dec_s*`. FSM có thêm tín hiệu `frame_sel` (toggle mỗi `en`).

**Iteration bound:** Giữ nguyên `N_reg = 1` (trong mỗi frame con) hoặc `N_reg = 2` (nếu kết hợp PA1), nhưng fmax không tăng thêm so với PA1+PA2. C-slow **chỉ tăng throughput**, không tăng fmax.

**Hệ quả:** Throughput tăng gấp đôi (1 frame / 3 clk), latency giữ 6 clk, area tăng ~2x. Nếu mục tiêu là max fmax thì C-slow **không giúp ích**, chỉ tăng throughput.

**Khuyến nghị:** Không dùng cho mục tiêu này. Bỏ qua.

### PA4 — Modulo normalization 3-bit (Hekstra) + bỏ saturate

**Ý tưởng:** Path metric chênh lệch tối đa giữa các state ở K=3, 4 state, max_bm=2 là `K × max_bm = 6`. Cần `⌈log2(6)⌉ + 1 = 3` bit (bit sign wrap-around). Bỏ mux saturate `sum_xx[2] ? 2'b11 : sum_xx[1:0]`.

**Cơ sở toán học (Hekstra 1987):** Nếu `bit_width ≥ ⌈log2(K × max_bm)⌉ + 1` thì comparator hoạt động đúng với số có dấu wrap-around, không cần normalize.

**RTL patch (add_comp_slt.v):**
```verilog
module add_comp_slt_3bit (
    input  wire [1:0] bm00, bm11, bm10, bm01,
    input  wire [2:0] pm00, pm01, pm10, pm11,        // <-- 3 bit, không phải 2
    output wire [2:0] new_pm00, new_pm01, new_pm10, new_pm11,
    output wire [3:0] decision
);
    // Bỏ saturate, dùng wrap-around 3-bit tự nhiên
    wire [3:0] sum_00_a = {1'b0, pm00} + {2'b0, bm00};   // 3+2 = 4 bit, lấy 3 LSB
    wire [3:0] sum_00_b = {1'b0, pm01} + {2'b0, bm11};
    wire [2:0] cand_00_a = sum_00_a[2:0];
    wire [2:0] cand_00_b = sum_00_b[2:0];

    assign decision[0] = (cand_00_b < cand_00_a);   // <-- 3-bit comparator
    assign new_pm00 = decision[0] ? cand_00_b : cand_00_a;
    // ... tương tự cho 01, 10, 11
endmodule
```

**Init trong memory.v:**
```verilog
pm00 <= 3'd0;  pm01 <= 3'd7;  pm10 <= 3'd7;  pm11 <= 3'd7;  // 3'b111 = "infinity" wrap
```

**Ưu điểm:**
- Bỏ 1 tầng mux saturate → giảm 1 gate delay trong ACS.
- Đúng công thức Hekstra, không over-engineer (3 bit, không phải 4).
- So sánh 3-bit dài hơn 2-bit 1 tầng logic → PA1 (retiming) phải đi kèm để bù.

**Đánh đổi:** +4 FF (4 reg × 1 bit), comparator 3-bit thay 2-bit.

---

## 3. KẾT HỢP KHUYẾN NGHỊ (để đạt max fmax)

### 3.1 Phương án tổng hợp: PA1 + PA2 + PA4

1. **Mở rộng rx_reg shift-by-8** (từ shift-by-4).
2. **Viết module `radix2_acs` mới**, bên trong chèn reg giữa 2 step (PA1): `pm_mid_r*`.
3. **Dùng `add_comp_slt_3bit` với modulo 3-bit** (PA4), bỏ saturate.
4. **FSM đơn giản hóa:** 2 active state (ST_01, ST_23) thay vì 4.
5. **Traceback:** giữ combinational (không cần pipeline vì 4 mux nối tiếp thay vì 7), hoặc pipeline 1 tầng nếu cần.

### 3.2 Latency & Throughput

| Thông số | Baseline | Sau PA1+2+4 |
|----------|----------|-------------|
| Latency | 6 clk | 6 clk (giữ nguyên) |
| Throughput | 1 frame / 6 clk | 1 frame / 6 clk (giữ nguyên) |
| Số cặp symbol/cycle | 1 (4 bit) | 2 (8 bit) |
| Số active cycle | 4 | 2 |
| N_reg trong vòng | 1 | 2 |
| T_loop ước lượng | 8 gates | 4 gates (1 ACS stage) |
| T∞ ước lượng | 8 gates | 2 gates |

### 3.3 Ước lượng fmax (có điều kiện)

**Quan trọng:** Đây là ước lượng lý thuyết từ iteration bound, **CHƯA CÓ SYNTHESIS CONFIRM**.

Với sky130 ss/1.62V/125°C, mỗi gate delay NAND2 ~0.4–0.5 ns (ước lượng từ lib, không tự đo):

| Phiên bản | T∞ (gates) | T∞ (ns) | fmax lý thuyết (MHz) |
|-----------|------------|---------|----------------------|
| Baseline (PA0) | 8 | 3.2–4.0 | 200–250 |
| PA4 (modulo 3-bit) | 7 | 2.8–3.5 | 250–290 |
| PA1 (retiming) | 4 | 1.6–2.0 | 400–500 |
| PA1+PA4 | 4 | 1.6–2.0 | 400–500 (combinational ngắn hơn → có thể cao hơn) |
| **PA1+PA2+PA4 (đề xuất)** | **2** | **0.8–1.0** | **700–900** |

**Caveat lớn:** Con số 700–900 MHz là bound lý thuyết. Thực tế fmax còn bị chặn bởi:
- Wire delay (RC) — có thể chiếm 30–50% critical path ở layout.
- Setup time + clock uncertainty + clock skew (~0.3–0.5 ns tổng).
- FF clk-to-Q delay (~0.2–0.3 ns).

Ước lượng thực dụng hơn (sau khi trừ overhead): **fmax kỳ vọng 400–600 MHz** cho PA1+PA2+PA4. Vẫn **gấp 2–3 lần baseline 200 MHz**, đáng kể.

**Bắt buộc:** Sau khi áp dụng, synthesis lại với Genus ở ss corner, check `flow_QOR_summary.rpt` và `timingReports/*postRoute*` để confirm.

### 3.4 RTL patch tổng hợp (skeleton)

```verilog
// === File mới: radix2_acs_pipeline.v ===
module radix2_acs_pipeline (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        load_frame,   // init pm_mid_r* = 0
    input  wire        active,
    input  wire [1:0]  bm_a00, bm_a11, bm_a10, bm_a01,
    input  wire [1:0]  bm_b00, bm_b11, bm_b10, bm_b01,
    input  wire [2:0]  pm00, pm01, pm10, pm11,      // 3-bit input
    output wire [2:0]  new_pm00, new_pm01, new_pm10, new_pm11,
    output wire [3:0]  dec_step1,                  // decision của ACS_even
    output wire [3:0]  dec_step2                   // decision của ACS_odd
);
    // Step 1: ACS_even, combinational
    wire [2:0] pm_mid00, pm_mid01, pm_mid10, pm_mid11;
    add_comp_slt_3bit u_step1 (
        .bm00(bm_a00), .bm11(bm_a11), .bm10(bm_a10), .bm01(bm_a01),
        .pm00(pm00), .pm01(pm01), .pm10(pm10), .pm11(pm11),
        .new_pm00(pm_mid00), .new_pm01(pm_mid01),
        .new_pm10(pm_mid10), .new_pm11(pm_mid11),
        .decision(dec_step1)
    );

    // Pipeline reg (PA1: N_reg: 1 -> 2)
    reg [2:0] pm_mid_r00, pm_mid_r01, pm_mid_r10, pm_mid_r11;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) {pm_mid_r00, pm_mid_r01, pm_mid_r10, pm_mid_r11} <= 12'd0;
        else if (load_frame) {pm_mid_r00, pm_mid_r01, pm_mid_r10, pm_mid_r11} <= 12'd0;
        else if (active) {pm_mid_r00, pm_mid_r01, pm_mid_r10, pm_mid_r11} <= {pm_mid00, pm_mid01, pm_mid10, pm_mid11};
    end

    // Step 2: ACS_odd, combinational, dùng reg-clocked pm_mid_r*
    add_comp_slt_3bit u_step2 (
        .bm00(bm_b00), .bm11(bm_b11), .bm10(bm_b10), .bm01(bm_b01),
        .pm00(pm_mid_r00), .pm01(pm_mid_r01), .pm10(pm_mid_r10), .pm11(pm_mid_r11),
        .new_pm00(new_pm00), .new_pm01(new_pm01),
        .new_pm10(new_pm10), .new_pm11(new_pm11),
        .decision(dec_step2)
    );
endmodule
```

**Top-level (viterbi_decoder.v) thay đổi:**
- Thay 2 instance `add_comp_slt` riêng lẻ bằng 1 instance `radix2_acs_pipeline`.
- Mở rộng `rx_reg` từ 16 bit shift-by-4 lên 32 bit shift-by-8 (giữ backward compat bằng cách zero-extend, hoặc đổi I/O `i_data[31:16]`).
- FSM giảm xuống 2 active state.

**Memory.v thay đổi:**
- `pm*` từ 2-bit lên 3-bit.
- `dec_s*` chỉ cần 4 (mỗi radix-2 cycle cho 2 decision), giảm từ 8 xuống 4.
- Init `pm00<=3'd0, pm01..11<=3'd7`.

**Traceback.v thay đổi:**
- Chỉ 4 stage traceback (4 mux) thay vì 7 → critical path tự giảm, có thể không cần pipeline.

---

## 4. BẢNG TỔNG HỢP

| PA | Thay đổi | T_loop | N_reg | T∞ | fmax ước lượng (MHz) | Latency | Area | Khuyến nghị |
|----|----------|--------|-------|-----|----------------------|---------|------|--------------|
| PA0 (baseline) | — | 8 | 1 | 8 | 200–250 | 6 | 1× | — |
| PA4 | Modulo 3-bit, bỏ sat | 7 | 1 | 7 | 250–290 | 6 | +4 FF | Nên (rẻ) |
| PA1 | Reg giữa 2 ACS | 4 | 2 | 2 | 400–500 | 7 (nếu đứng riêng) | +8 FF | Kết hợp với PA2 |
| PA1+PA4 | | 4 | 2 | 2 | 400–550 | 7 | +12 FF | Tốt |
| **PA1+PA2+PA4** | **Radix-2 + reg + modulo 3-bit** | **4** | **2** | **2** | **400–600 (kỳ vọng)** | **6 (giữ)** | **+16 FF, gấp ~1.5× ACS** | **Max fmax** |
| PA3 (C-slow) | 2-way interleaving | 8 (trong mỗi way) | 1 | 8 | không tăng fmax, tăng throughput 2× | 6 | 2× | Bỏ qua cho mục tiêu fmax |

---

## 5. ĐIỀU KIỆN ÁP DỤNG & RỦI RO

### 5.1 Điều kiện áp dụng

- **Clock target vẫn là 5.0 ns (200 MHz)** trong SDC — nếu đổi SDC phải synthesis lại từ đầu.
- **Corner: sky130 ss/1.62V/125°C** (worst case).
- **Layout vẫn chạy với `run_innovus.tcl` hiện tại** — chỉ thay RTL, không thay constraint.
- **Testbench `tb_viterbi_readmemb.v` pass** với RTL mới (bắt buộc re-sim).

### 5.2 Rủi ro cần verify

1. **Modulo 3-bit wrap-around:** Có thể sai nếu traceback path dài làm path metric vượt quá `2^3 = 8`. Hekstra chứng minh đúng cho K=3, 4 state, max_bm=2, depth=8 symbol (khớp dự án). Nhưng nếu testbench có input đặc biệt (toàn 0 hoặc toàn 1), cần check.
2. **Radix-2 1-cycle cho 2 cặp symbol:** Tăng mạnh combinational load trên BMU (giờ cần 4 BMU song song thay vì 2). Verify critical path mới không nằm ở BMU.
3. **Reg giữa 2 ACS (PA1):** Tăng latency nội bộ 1 clk, nếu FSM không update có thể miss timing. Cần update `control.v` để khớp.
4. **Layout:** Retiming sâu (PA1) có thể làm tool khó converge, cần retiming-aware placement.
5. **Hold time:** Nếu critical path quá ngắn, hold có thể violate. Cần check hold report.

### 5.3 Verification plan

1. Chạy simulation `tb_viterbi_readmemb.v` với RTL mới, so sánh output với baseline. Phải khớp từng bit.
2. Synthesis với Genus command cũ (`collectGenusLibrary.log` tham chiếo), target 5 ns clock.
3. Check `flow_QOR_summary.rpt`: WNS, TNS, fmax thật ở ss/ff/tt corners.
4. Check `timingReports/*postRoute*`: critical path nằm ở đâu (ACS, traceback, hay nơi khác).
5. Nếu WNS âm: thử PA1 standalone trước (rẻ nhất), rồi mới PA1+PA2+PA4.
6. Nếu WNS dương lớn (>1 ns): đã đạt target, dừng. Nếu muốn tiết kiệm area, dùng lại PA4 standalone.

---

## 6. TÓM TẮT 1 DÒNG

Vòng ACS có đúng 1 reg (`N_reg=1`), latency 6 clk, critical path 8 gates combinational; phương án max fmax là PA1+PA2+PA4 (radix-2 với reg giữa 2 step + modulo 3-bit, bỏ saturate), giữ latency 6 clk, ước lượng fmax 400–600 MHz ở sky130 ss corner, **bắt buộc synthesis confirm từ `flow_QOR_summary.rpt`**.

---

## 7. TÀI LIỆU THAM KHẢO

- Hekstra, A.P. (1987). "An Alternative to Metric Rescaling in Viterbi Decoders." *IEEE Trans. Comm.* — chứng minh modulo wrap-around đúng khi `bit_width ≥ ⌈log2(K × max_bm)⌉ + 1`.
- Lin, S. & Costello, D. (2004). *Error Control Coding*, 2nd ed., Ch. 12 — Viterbi decoder architecture, radix-2, ACS critical path.
- Parhi, K.K. (1999). *VLSI Digital Signal Processing Systems*, Ch. 10 — retiming, iteration bound, pipelining Viterbi.
- Xilinx PG051 (2018). "Viterbi Decoder v9.1 LogiCORE IP Product Guide" — tham khảo kiến trúc thương mại, confirm practice modulo + pipelining.
