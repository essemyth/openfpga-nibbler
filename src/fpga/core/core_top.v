//
// User core top-level
//
// Instantiated by the real top-level: apf_top
//

`default_nettype none

module core_top (

//
// physical connections
//

///////////////////////////////////////////////////
// clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

input   wire            clk_74a, // mainclk1
input   wire            clk_74b, // mainclk1 

///////////////////////////////////////////////////
// cartridge interface
// switches between 3.3v and 5v mechanically
// output enable for multibit translators controlled by pic32

// GBA AD[15:8]
inout   wire    [7:0]   cart_tran_bank2,
output  wire            cart_tran_bank2_dir,

// GBA AD[7:0]
inout   wire    [7:0]   cart_tran_bank3,
output  wire            cart_tran_bank3_dir,

// GBA A[23:16]
inout   wire    [7:0]   cart_tran_bank1,
output  wire            cart_tran_bank1_dir,

// GBA [7] PHI#
// GBA [6] WR#
// GBA [5] RD#
// GBA [4] CS1#/CS#
//     [3:0] unwired
inout   wire    [7:4]   cart_tran_bank0,
output  wire            cart_tran_bank0_dir,

// GBA CS2#/RES#
inout   wire            cart_tran_pin30,
output  wire            cart_tran_pin30_dir,
// when GBC cart is inserted, this signal when low or weak will pull GBC /RES low with a special circuit
// the goal is that when unconfigured, the FPGA weak pullups won't interfere.
// thus, if GBC cart is inserted, FPGA must drive this high in order to let the level translators
// and general IO drive this pin.
output  wire            cart_pin30_pwroff_reset,

// GBA IRQ/DRQ
inout   wire            cart_tran_pin31,
output  wire            cart_tran_pin31_dir,

// infrared
input   wire            port_ir_rx,
output  wire            port_ir_tx,
output  wire            port_ir_rx_disable, 

// GBA link port
inout   wire            port_tran_si,
output  wire            port_tran_si_dir,
inout   wire            port_tran_so,
output  wire            port_tran_so_dir,
inout   wire            port_tran_sck,
output  wire            port_tran_sck_dir,
inout   wire            port_tran_sd,
output  wire            port_tran_sd_dir,
 
///////////////////////////////////////////////////
// cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

output  wire    [21:16] cram0_a,
inout   wire    [15:0]  cram0_dq,
input   wire            cram0_wait,
output  wire            cram0_clk,
output  wire            cram0_adv_n,
output  wire            cram0_cre,
output  wire            cram0_ce0_n,
output  wire            cram0_ce1_n,
output  wire            cram0_oe_n,
output  wire            cram0_we_n,
output  wire            cram0_ub_n,
output  wire            cram0_lb_n,

output  wire    [21:16] cram1_a,
inout   wire    [15:0]  cram1_dq,
input   wire            cram1_wait,
output  wire            cram1_clk,
output  wire            cram1_adv_n,
output  wire            cram1_cre,
output  wire            cram1_ce0_n,
output  wire            cram1_ce1_n,
output  wire            cram1_oe_n,
output  wire            cram1_we_n,
output  wire            cram1_ub_n,
output  wire            cram1_lb_n,

///////////////////////////////////////////////////
// sdram, 512mbit 16bit

output  wire    [12:0]  dram_a,
output  wire    [1:0]   dram_ba,
inout   wire    [15:0]  dram_dq,
output  wire    [1:0]   dram_dqm,
output  wire            dram_clk,
output  wire            dram_cke,
output  wire            dram_ras_n,
output  wire            dram_cas_n,
output  wire            dram_we_n,

///////////////////////////////////////////////////
// sram, 1mbit 16bit

output  wire    [16:0]  sram_a,
inout   wire    [15:0]  sram_dq,
output  wire            sram_oe_n,
output  wire            sram_we_n,
output  wire            sram_ub_n,
output  wire            sram_lb_n,

///////////////////////////////////////////////////
// vblank driven by dock for sync in a certain mode

input   wire            vblank,

///////////////////////////////////////////////////
// i/o to 6515D breakout usb uart

output  wire            dbg_tx,
input   wire            dbg_rx,

///////////////////////////////////////////////////
// i/o pads near jtag connector user can solder to

output  wire            user1,
input   wire            user2,

///////////////////////////////////////////////////
// RFU internal i2c bus 

inout   wire            aux_sda,
output  wire            aux_scl,

///////////////////////////////////////////////////
// RFU, do not use
output  wire            vpll_feed,


//
// logical connections
//

///////////////////////////////////////////////////
// video, audio output to scaler
output  wire    [23:0]  video_rgb,
output  wire            video_rgb_clock,
output  wire            video_rgb_clock_90,
output  wire            video_de,
output  wire            video_skip,
output  wire            video_vs,
output  wire            video_hs,
    
output  wire            audio_mclk,
input   wire            audio_adc,
output  wire            audio_dac,
output  wire            audio_lrck,

///////////////////////////////////////////////////
// bridge bus connection
// synchronous to clk_74a
output  wire            bridge_endian_little,
input   wire    [31:0]  bridge_addr,
input   wire            bridge_rd,
output  reg     [31:0]  bridge_rd_data,
input   wire            bridge_wr,
input   wire    [31:0]  bridge_wr_data,

///////////////////////////////////////////////////
// controller data
// 
// key bitmap:
//   [0]    dpad_up
//   [1]    dpad_down
//   [2]    dpad_left
//   [3]    dpad_right
//   [4]    face_a
//   [5]    face_b
//   [6]    face_x
//   [7]    face_y
//   [8]    trig_l1
//   [9]    trig_r1
//   [10]   trig_l2
//   [11]   trig_r2
//   [12]   trig_l3
//   [13]   trig_r3
//   [14]   face_select
//   [15]   face_start
//   [31:28] type
// joy values - unsigned
//   [ 7: 0] lstick_x
//   [15: 8] lstick_y
//   [23:16] rstick_x
//   [31:24] rstick_y
// trigger values - unsigned
//   [ 7: 0] ltrig
//   [15: 8] rtrig
//
input   wire    [31:0]  cont1_key,
input   wire    [31:0]  cont2_key,
input   wire    [31:0]  cont3_key,
input   wire    [31:0]  cont4_key,
input   wire    [31:0]  cont1_joy,
input   wire    [31:0]  cont2_joy,
input   wire    [31:0]  cont3_joy,
input   wire    [31:0]  cont4_joy,
input   wire    [15:0]  cont1_trig,
input   wire    [15:0]  cont2_trig,
input   wire    [15:0]  cont3_trig,
input   wire    [15:0]  cont4_trig
    
);

// not using the IR port, so turn off both the LED, and
// disable the receive circuit to save power
assign port_ir_tx = 0;
assign port_ir_rx_disable = 1;

// bridge endianness
assign bridge_endian_little = 0;

// cart is unused, so set all level translators accordingly
// directions are 0:IN, 1:OUT
assign cart_tran_bank3 = 8'hzz;
assign cart_tran_bank3_dir = 1'b0;
assign cart_tran_bank2 = 8'hzz;
assign cart_tran_bank2_dir = 1'b0;
assign cart_tran_bank1 = 8'hzz;
assign cart_tran_bank1_dir = 1'b0;
assign cart_tran_bank0 = 4'hf;
assign cart_tran_bank0_dir = 1'b1;
assign cart_tran_pin30 = 1'b0;      // reset or cs2, we let the hw control it by itself
assign cart_tran_pin30_dir = 1'bz;
assign cart_pin30_pwroff_reset = 1'b0;  // hardware can control this
assign cart_tran_pin31 = 1'bz;      // input
assign cart_tran_pin31_dir = 1'b0;  // input

// link port is unused, set to input only to be safe
// each bit may be bidirectional in some applications
assign port_tran_so = 1'bz;
assign port_tran_so_dir = 1'b0;     // SO is output only
assign port_tran_si = 1'bz;
assign port_tran_si_dir = 1'b0;     // SI is input only
assign port_tran_sck = 1'bz;
assign port_tran_sck_dir = 1'b0;    // clock direction can change
assign port_tran_sd = 1'bz;
assign port_tran_sd_dir = 1'b0;     // SD is input and not used

// tie off the rest of the pins we are not using
assign cram0_a = 'h0;
assign cram0_dq = {16{1'bZ}};
assign cram0_clk = 0;
assign cram0_adv_n = 1;
assign cram0_cre = 0;
assign cram0_ce0_n = 1;
assign cram0_ce1_n = 1;
assign cram0_oe_n = 1;
assign cram0_we_n = 1;
assign cram0_ub_n = 1;
assign cram0_lb_n = 1;

assign cram1_a = 'h0;
assign cram1_dq = {16{1'bZ}};
assign cram1_clk = 0;
assign cram1_adv_n = 1;
assign cram1_cre = 0;
assign cram1_ce0_n = 1;
assign cram1_ce1_n = 1;
assign cram1_oe_n = 1;
assign cram1_we_n = 1;
assign cram1_ub_n = 1;
assign cram1_lb_n = 1;

assign dram_a = 'h0;
assign dram_ba = 'h0;
assign dram_dq = {16{1'bZ}};
assign dram_dqm = 'h0;
assign dram_clk = 'h0;
assign dram_cke = 'h0;
assign dram_ras_n = 'h1;
assign dram_cas_n = 'h1;
assign dram_we_n = 'h1;

assign sram_a = 'h0;
assign sram_dq = {16{1'bZ}};
assign sram_oe_n  = 1;
assign sram_we_n  = 1;
assign sram_ub_n  = 1;
assign sram_lb_n  = 1;

assign dbg_tx = 1'bZ;
assign user1 = 1'bZ;
assign aux_scl = 1'bZ;
assign vpll_feed = 1'bZ;


// for bridge write data, we just broadcast it to all bus devices
// for bridge read data, we have to mux it
// add your own devices here
    wire    [31:0]  ss_bridge_rd_data;      // save state buffer (nibbler_savestate)
    wire    [31:0]  hs_bridge_rd_data;      // high score file (nibbler_hiscore)

always @(*) begin
    casex(bridge_addr)
    default: begin
        bridge_rd_data <= 0;
    end
    32'h4xxxxxxx: begin
        // save state transfer buffer
        bridge_rd_data <= ss_bridge_rd_data;
    end
    32'h6xxxxxxx: begin
        // high score save file
        bridge_rd_data <= hs_bridge_rd_data;
    end
    32'hF8xxxxxx: begin
        bridge_rd_data <= cmd_bridge_rd_data;
    end
    endcase
end


//
// host/target command handler
//
    wire            reset_n;                // driven by host commands, can be used as core-wide reset
    wire    [31:0]  cmd_bridge_rd_data;
    
// bridge host commands
// synchronous to clk_74a
    wire            status_boot_done = pll_core_locked_s; 
    wire            status_setup_done = pll_core_locked_s; // rising edge triggers a target command
    wire            status_running = reset_n; // we are running as soon as reset_n goes high

    wire            dataslot_requestread;
    wire    [15:0]  dataslot_requestread_id;
    wire            dataslot_requestread_ack = 1;
    wire            dataslot_requestread_ok = 1;

    wire            dataslot_requestwrite;
    wire    [15:0]  dataslot_requestwrite_id;
    wire    [31:0]  dataslot_requestwrite_size;
    wire            dataslot_requestwrite_ack = 1;
    wire            dataslot_requestwrite_ok = 1;

    wire            dataslot_update;
    wire    [15:0]  dataslot_update_id;
    wire    [31:0]  dataslot_update_size;
    
    wire            dataslot_allcomplete;

    wire     [31:0] rtc_epoch_seconds;
    wire     [31:0] rtc_date_bcd;
    wire     [31:0] rtc_time_bcd;
    wire            rtc_valid;

    // save states: 8448 bytes (RAM + registers) at bridge 0x40000000, see nibbler_savestate.v
    wire            savestate_supported = 1'b1;
    wire    [31:0]  savestate_addr = 32'h40000000;
    wire    [31:0]  savestate_size = 32'h00002100;
    wire    [31:0]  savestate_maxloadsize = 32'h00002100;

    wire            savestate_start;
    wire            savestate_start_ack;
    wire            savestate_start_busy;
    wire            savestate_start_ok;
    wire            savestate_start_err;

    wire            savestate_load;
    wire            savestate_load_ack;
    wire            savestate_load_busy;
    wire            savestate_load_ok;
    wire            savestate_load_err;
    
    wire            osnotify_inmenu;

// bridge target commands
// synchronous to clk_74a

    reg             target_dataslot_read;       
    reg             target_dataslot_write;
    reg             target_dataslot_getfile;    // require additional param/resp structs to be mapped
    reg             target_dataslot_openfile;   // require additional param/resp structs to be mapped
    
    wire            target_dataslot_ack;        
    wire            target_dataslot_done;
    wire    [2:0]   target_dataslot_err;

    reg     [15:0]  target_dataslot_id;
    reg     [31:0]  target_dataslot_slotoffset;
    reg     [31:0]  target_dataslot_bridgeaddr;
    reg     [31:0]  target_dataslot_length;
    
    wire    [31:0]  target_buffer_param_struct; // to be mapped/implemented when using some Target commands
    wire    [31:0]  target_buffer_resp_struct;  // to be mapped/implemented when using some Target commands
    
// bridge data slot access
// synchronous to clk_74a

    // The data table holds {id, size} per data slot (index * 2, index * 2 + 1).
    // APF saves a nonvolatile slot using the size in this table, so keep the
    // High Scores slot (index 1) at its full 256 bytes; APF records 0 when no
    // save file exists yet.
    wire    [9:0]   datatable_addr = 10'd3;
    wire            datatable_wren = 1'b1;
    wire    [31:0]  datatable_data = 32'h00000100;
    wire    [31:0]  datatable_q;

core_bridge_cmd icb (

    .clk                ( clk_74a ),
    .reset_n            ( reset_n ),

    .bridge_endian_little   ( bridge_endian_little ),
    .bridge_addr            ( bridge_addr ),
    .bridge_rd              ( bridge_rd ),
    .bridge_rd_data         ( cmd_bridge_rd_data ),
    .bridge_wr              ( bridge_wr ),
    .bridge_wr_data         ( bridge_wr_data ),
    
    .status_boot_done       ( status_boot_done ),
    .status_setup_done      ( status_setup_done ),
    .status_running         ( status_running ),

    .dataslot_requestread       ( dataslot_requestread ),
    .dataslot_requestread_id    ( dataslot_requestread_id ),
    .dataslot_requestread_ack   ( dataslot_requestread_ack ),
    .dataslot_requestread_ok    ( dataslot_requestread_ok ),

    .dataslot_requestwrite      ( dataslot_requestwrite ),
    .dataslot_requestwrite_id   ( dataslot_requestwrite_id ),
    .dataslot_requestwrite_size ( dataslot_requestwrite_size ),
    .dataslot_requestwrite_ack  ( dataslot_requestwrite_ack ),
    .dataslot_requestwrite_ok   ( dataslot_requestwrite_ok ),

    .dataslot_update            ( dataslot_update ),
    .dataslot_update_id         ( dataslot_update_id ),
    .dataslot_update_size       ( dataslot_update_size ),
    
    .dataslot_allcomplete   ( dataslot_allcomplete ),

    .rtc_epoch_seconds      ( rtc_epoch_seconds ),
    .rtc_date_bcd           ( rtc_date_bcd ),
    .rtc_time_bcd           ( rtc_time_bcd ),
    .rtc_valid              ( rtc_valid ),
    
    .savestate_supported    ( savestate_supported ),
    .savestate_addr         ( savestate_addr ),
    .savestate_size         ( savestate_size ),
    .savestate_maxloadsize  ( savestate_maxloadsize ),

    .savestate_start        ( savestate_start ),
    .savestate_start_ack    ( savestate_start_ack ),
    .savestate_start_busy   ( savestate_start_busy ),
    .savestate_start_ok     ( savestate_start_ok ),
    .savestate_start_err    ( savestate_start_err ),

    .savestate_load         ( savestate_load ),
    .savestate_load_ack     ( savestate_load_ack ),
    .savestate_load_busy    ( savestate_load_busy ),
    .savestate_load_ok      ( savestate_load_ok ),
    .savestate_load_err     ( savestate_load_err ),

    .osnotify_inmenu        ( osnotify_inmenu ),
    
    .target_dataslot_read       ( target_dataslot_read ),
    .target_dataslot_write      ( target_dataslot_write ),
    .target_dataslot_getfile    ( target_dataslot_getfile ),
    .target_dataslot_openfile   ( target_dataslot_openfile ),
    
    .target_dataslot_ack        ( target_dataslot_ack ),
    .target_dataslot_done       ( target_dataslot_done ),
    .target_dataslot_err        ( target_dataslot_err ),

    .target_dataslot_id         ( target_dataslot_id ),
    .target_dataslot_slotoffset ( target_dataslot_slotoffset ),
    .target_dataslot_bridgeaddr ( target_dataslot_bridgeaddr ),
    .target_dataslot_length     ( target_dataslot_length ),

    .target_buffer_param_struct ( target_buffer_param_struct ),
    .target_buffer_resp_struct  ( target_buffer_resp_struct ),
    
    .datatable_addr         ( datatable_addr ),
    .datatable_wren         ( datatable_wren ),
    .datatable_data         ( datatable_data ),
    .datatable_q            ( datatable_q )

);



////////////////////////////////////////////////////////////////////////////////////////



// Nibbler
//
// The arcade board runs on clk_sys. It starts once nibbler.rom is loaded and
// APF releases reset, or as soon as a save state load arrives (waking from
// sleep: APF restores the state before releasing reset). After that APF's
// reset is ignored: APF enters/exits reset around save state loads, and
// obeying it would wipe the restored game. "Reset Game" in the core menu
// restarts it instead.

    wire        reset_n_s, allcomplete_s;
synch_3 s_rst  ( reset_n, reset_n_s, clk_sys );
synch_3 s_load ( dataslot_allcomplete, allcomplete_s, clk_sys );

    wire        inmenu_s, ss_start_s, ss_load_s;     // synchronized below
    reg         nib_started = 1'b0;
    reg  [7:0]  user_reset = 8'd0;
    reg         user_reset_prev = 1'b0;
    wire        user_reset_s;
    reg         nib_reset = 1'b1;
always @(posedge clk_sys) begin
    if (allcomplete_s && (reset_n_s || ss_load_s)) nib_started <= 1'b1;
    user_reset_prev <= user_reset_s;
    if (user_reset_s != user_reset_prev) user_reset <= 8'hFF;      // toggled from the menu
    else if (user_reset != 8'd0) user_reset <= user_reset - 8'd1;
    nib_reset <= !nib_started || user_reset != 8'd0;
end

// Controls (see input.json). Player 1 is controller 1; controller 2 drives the
// player 2 port, which the game only reads in cocktail mode.
//   D-pad   4-way joystick (newest direction wins)
//   Select  coin
//   Start   1 player start
//   Y       2 players start
    wire [15:0] keys1, keys2;
synch_3 #(.WIDTH(16)) s_keys1 ( cont1_key[15:0], keys1, clk_sys );
synch_3 #(.WIDTH(16)) s_keys2 ( cont2_key[15:0], keys2, clk_sys );

    wire [3:0]  joy1, joy2;     // {right, left, down, up}
joy4way j1 ( clk_sys, keys1[3:0], joy1 );
joy4way j2 ( clk_sys, keys2[3:0], joy2 );

// A coin switch closes briefly however long the button is held: pulse coin
// for about 2 frames (33 ms) on each press of Select.
    localparam  COIN_PULSE = 21'd1509120;
    reg  [20:0] coin_timer = 21'd0;
    reg         select_prev = 1'b0;
always @(posedge clk_sys) begin
    select_prev <= keys1[14];
    if (keys1[14] && !select_prev)
        coin_timer <= COIN_PULSE;
    else if (coin_timer != 21'd0)
        coin_timer <= coin_timer - 21'd1;
end
    wire        coin1 = coin_timer != 21'd0;

    // port bits: left, right, up, down in 7-4
    wire [7:0]  nib_in0 = {joy1[2], joy1[3], joy1[0], joy1[1], 4'b0000};
    wire [7:0]  nib_in1 = {joy2[2], joy2[3], joy2[0], joy2[1], 4'b0000};
    wire [7:0]  nib_in2 = {keys1[15], keys1[7], 4'b0000, coin1, 1'b0};    // start1, start2, -, coin1, coin2

// Settings from the Pocket menu (interact.json), written over the bridge.
// APF writes persisted values before releasing reset.
//   0x50000000 bit 0     debug overlay
//   0x50000010 bits 1-0  lives            (DSW 1-0)
//   0x50000014 bit 0     difficulty hard  (DSW 2)
//   0x50000018 bit 0     service mode     (DSW 4)
//   0x5000001C bit 0     free play        (DSW 5)
//   0x50000020 bits 1-0  coinage          (DSW 7-6)
//   0x50000030           Reset Game action (each write restarts the game)
    reg         set_debug = 1'b0;
    reg  [1:0]  set_lives = 2'd0, set_coinage = 2'd0;
    reg         set_hard = 1'b0, set_service = 1'b0, set_freeplay = 1'b0;
    reg         reset_toggle = 1'b0;
always @(posedge clk_74a) begin
    if (bridge_wr) begin
        case (bridge_addr)
            32'h50000030: reset_toggle <= ~reset_toggle;
            32'h50000000: set_debug    <= bridge_wr_data[0];
            32'h50000010: set_lives    <= bridge_wr_data[1:0];
            32'h50000014: set_hard     <= bridge_wr_data[0];
            32'h50000018: set_service  <= bridge_wr_data[0];
            32'h5000001C: set_freeplay <= bridge_wr_data[0];
            32'h50000020: set_coinage  <= bridge_wr_data[1:0];
            default: ;
        endcase
    end
end

    wire        show_debug;
    wire [7:0]  nib_dsw;
synch_3 s_dbg ( set_debug, show_debug, clk_sys );
synch_3 s_ureset ( reset_toggle, user_reset_s, clk_sys );
synch_3 #(.WIDTH(8)) s_dsw (
    {set_coinage, set_freeplay, set_service, 1'b0 /* upright */, set_hard, set_lives},
    nib_dsw, clk_sys );

// Pause while the Pocket menu is open; save state handshake. The board works
// in clk_sys, APF in clk_74a.
synch_3 #(.WIDTH(3)) s_ss_in (
    {osnotify_inmenu, savestate_start, savestate_load},
    {inmenu_s, ss_start_s, ss_load_s}, clk_sys );

    wire        ss_ack, ss_busy, ss_ok, ss_err;
    wire        ss_ack_s, ss_busy_s, ss_ok_s, ss_err_s;
synch_3 #(.WIDTH(4)) s_ss_out (
    {ss_ack, ss_busy, ss_ok, ss_err},
    {ss_ack_s, ss_busy_s, ss_ok_s, ss_err_s}, clk_74a );

// one operation at a time, so both report the same status
assign savestate_start_ack  = ss_ack_s;
assign savestate_start_busy = ss_busy_s;
assign savestate_start_ok   = ss_ok_s;
assign savestate_start_err  = ss_err_s;
assign savestate_load_ack   = ss_ack_s;
assign savestate_load_busy  = ss_busy_s;
assign savestate_load_ok    = ss_ok_s;
assign savestate_load_err   = ss_err_s;

    wire [23:0] vid_rgb;
    wire        vid_de, vid_hs, vid_vs;
    wire [15:0] nib_audio;
    wire        nib_audio_valid;

nibbler_top nibbler (
    .clk_sys        ( clk_sys ),
    .reset          ( nib_reset ),

    .clk_74a        ( clk_74a ),
    .bridge_wr      ( bridge_wr ),
    .bridge_rd      ( bridge_rd ),
    .bridge_addr    ( bridge_addr ),
    .bridge_wr_data ( bridge_wr_data ),
    .ss_bridge_rd_data ( ss_bridge_rd_data ),
    .hs_bridge_rd_data ( hs_bridge_rd_data ),

    .in0            ( nib_in0 ),
    .in1            ( nib_in1 ),
    .in2            ( nib_in2 ),
    .dsw            ( nib_dsw ),

    .show_debug     ( show_debug ),
    .pause          ( inmenu_s ),

    .ss_start       ( ss_start_s ),
    .ss_load        ( ss_load_s ),
    .ss_ack         ( ss_ack ),
    .ss_busy        ( ss_busy ),
    .ss_ok          ( ss_ok ),
    .ss_err         ( ss_err ),

    .rgb            ( vid_rgb ),
    .de             ( vid_de ),
    .hs             ( vid_hs ),
    .vs             ( vid_vs ),

    .audio          ( nib_audio ),
    .audio_valid    ( nib_audio_valid )
);

// Hand video to the scaler on the pixel clock. clk_vid is exactly clk_sys / 8
// from the same PLL, and the video signals hold for 8 clk_sys cycles, so each
// clk_vid edge samples each pixel exactly once.
    reg [23:0]  vidout_rgb;
    reg         vidout_de, vidout_hs, vidout_vs;

always @(posedge clk_vid) begin
    vidout_rgb <= vid_rgb;
    vidout_de  <= vid_de;
    vidout_hs  <= vid_hs;
    vidout_vs  <= vid_vs;
end

assign video_rgb_clock = clk_vid;
assign video_rgb_clock_90 = clk_vid_90;
assign video_rgb = vidout_rgb;
assign video_de = vidout_de;
assign video_skip = 1'b0;
assign video_vs = vidout_vs;
assign video_hs = vidout_hs;




//
// Audio: 48 kHz, 16-bit I2S, the mono game sound on both channels.
//
// Samples cross from clk_sys with a toggle handshake: clk_sys stores each new
// sample and flips aud_toggle; the audio side, two flops later, sees the flip
// and takes the (by then long stable) sample.

assign audio_mclk = audgen_mclk;
assign audio_dac = audgen_dac;
assign audio_lrck = audgen_lrck;

// generate MCLK = 12.288mhz with fractional accumulator
    reg         [21:0]  audgen_accum;
    reg                 audgen_mclk;
    parameter   [20:0]  CYCLE_48KHZ = 21'd122880 * 2;
always @(posedge clk_74a) begin
    audgen_accum <= audgen_accum + CYCLE_48KHZ;
    if(audgen_accum >= 21'd742500) begin
        audgen_mclk <= ~audgen_mclk;
        audgen_accum <= audgen_accum - 21'd742500 + CYCLE_48KHZ;
    end
end

// generate SCLK = 3.072mhz by dividing MCLK by 4
    reg [1:0]   aud_mclk_divider;
    wire        audgen_sclk = aud_mclk_divider[1] /* synthesis keep*/;
    reg         audgen_lrck_1;
always @(posedge audgen_mclk) begin
    aud_mclk_divider <= aud_mclk_divider + 1'b1;
end

// sample handoff from clk_sys
    reg     [15:0]  aud_hold = 16'd0;
    reg             aud_toggle = 1'b0;
always @(posedge clk_sys) begin
    if (nib_audio_valid) begin
        aud_hold   <= nib_audio;
        aud_toggle <= ~aud_toggle;
    end
end

    reg     [2:0]   aud_toggle_s = 3'd0;
    reg     [15:0]  aud_sample = 16'd0;
always @(posedge audgen_sclk) begin
    aud_toggle_s <= {aud_toggle_s[1:0], aud_toggle};
    if (aud_toggle_s[2] != aud_toggle_s[1]) aud_sample <= aud_hold;
end

// shift out audio data as I2S
// 32 total bits per channel: 16 data bits, MSB first, starting one SCLK after
// LRCK changes, then 16 zero bits
//
    reg     [4:0]   audgen_lrck_cnt;
    reg             audgen_lrck;
    reg             audgen_dac;
    reg     [15:0]  audgen_word;
always @(negedge audgen_sclk) begin
    // 48khz * 64
    audgen_lrck_cnt <= audgen_lrck_cnt + 1'b1;
    if(audgen_lrck_cnt == 31) begin
        // switch channels
        audgen_lrck <= ~audgen_lrck;
        audgen_word <= aud_sample;
    end
    audgen_dac <= audgen_lrck_cnt < 5'd16 ? audgen_word[5'd15 - audgen_lrck_cnt] : 1'b0;
end


///////////////////////////////////////////////


    wire    clk_sys;
    wire    clk_vid;
    wire    clk_vid_90;

    wire    pll_core_locked;
    wire    pll_core_locked_s;
synch_3 s01(pll_core_locked, pll_core_locked_s, clk_74a);

pll_nibbler pll (
    .refclk     ( clk_74a ),
    .rst        ( 1'b0 ),
    .clk_sys    ( clk_sys ),
    .clk_vid    ( clk_vid ),
    .clk_vid_90 ( clk_vid_90 ),
    .locked     ( pll_core_locked )
);



endmodule
