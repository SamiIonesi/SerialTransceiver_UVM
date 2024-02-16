interface SerialTranceiver_itf;
  
  //inputs
  logic [31:0] DataIn;
  logic Sample;
  logic StartTx;
  logic Reset;
  logic Clk;
  logic ClkTx;
  //outputs
  logic TxDone;
  logic TxBusy;
  logic Dout;
  
endinterface



class transaction;
  
  //inputs
  rand logic [31:0] DataIn;
  logic Sample;
  logic StartTx;
  //outputs
  logic TxDone;
  logic TxBusy;
  logic Dout;
  
  function void display(input string tag);
    $display("[%0t]:[%0s] -> DataIn: %0h, Sample: %0b, StartTx: %0b, TxDone: %0b, TxBusy: %0b, Dout: %0b", $time(), tag, DataIn, Sample, StartTx, TxDone, TxBusy, Dout);
  endfunction
  
  function transaction copy();
    copy = new();
    copy.DataIn = this.DataIn;
    copy.Sample = this.Sample;
    copy.StartTx = this.StartTx;
    copy.TxDone = this.TxDone;
    copy.TxBusy = this.TxBusy;
    copy.Dout = this.Dout;
  endfunction
  
endclass



class generator;
  
  transaction trans;
  mailbox #(transaction) mbx_gd;
  event done;
  event drv_next;
  event sco_next;
  int count = 0;
  
  function new(mailbox #(transaction) mbx_gd);
    this.mbx_gd = mbx_gd;
    trans = new();
  endfunction
  
  task main();
    repeat(count) begin
      assert(trans.randomize) else $display("Randomize failed.");
      trans.display ("GEN");
      mbx_gd.put(trans.copy);
      @(drv_next);
      @(sco_next);
    end
    ->done;
  endtask
  
endclass



class driver;
  virtual SerialTranceiver_itf itf;
  transaction trans;
  mailbox #(transaction) mbx_gd;
  mailbox #(logic [31:0]) mbx_ds;
  event drv_next;
  
  logic [31:0] DataIn;
  
  function new(mailbox #(transaction) mbx_gd, mailbox #(logic [31:0]) mbx_ds);
    this.mbx_gd = mbx_gd;
    this.mbx_ds = mbx_ds;
  endfunction
  
  task reset();
    itf.DataIn <= 32'h0;
    itf.Sample <= 1'b0;
    itf.StartTx <= 1'b0;
    itf.Reset <= 1'b1;
    repeat(3) @(posedge itf.Clk);
    itf.Reset <= 1'b0;
    repeat(2) @(posedge itf.Clk);
    
    $display("[DRV] -> Reset Done.");
    $display("------------------------------------");
  endtask
  
  task main();
    forever begin
      mbx_gd.get(trans);
      itf.DataIn <= 32'h00;
      itf.Sample <= 1'b0;
      itf.StartTx <= 1'b0;
      @(negedge itf.Clk);
      itf.DataIn <= trans.DataIn;
      itf.Sample <= 1'b1;
      itf.StartTx <= 1'b0;
      mbx_ds.put(trans.DataIn);
      @(negedge itf.Clk);
      itf.Sample <= 1'b0;
      itf.StartTx <= 1'b1;
      wait(itf.TxBusy == 1'b1);
      $display("[%0t]:[DRV] -> Transfer started! Data Sent to Serial: %0h", $time(), trans.DataIn);
      wait(itf.TxDone == 1'b0);
      itf.DataIn <= 32'h00;
      itf.Sample <= 1'b0;
      itf.StartTx <= 1'b0;
      ->drv_next;
    end
  endtask
  
endclass

class monitor;
  
  virtual SerialTranceiver_itf itf;
  transaction trans;
  mailbox #(logic [31:0]) mbx_ms;
  
  logic [31:0] SerialData;
  
  function new(mailbox #(logic [31:0]) mbx_ms);
    this.mbx_ms = mbx_ms;
  endfunction
  
  task main();
    forever begin
      wait(itf.TxBusy == 1'b1);
      
      for(int i = 0; i <= 31; i++) begin
        @(negedge itf.ClkTx);
        SerialData[31 - i] = itf.Dout;
      end
      
      wait(itf.TxDone == 1'b1);
      @(posedge itf.ClkTx);
      
      $display("[%0t]:[MON] -> Transfer Ended! Data Sent = %0h.", $time(), SerialData);
      mbx_ms.put(SerialData);
    end
    
  endtask
  
endclass



class scoreboard;
  mailbox #(logic [31:0]) mbx_ds;
  mailbox #(logic [31:0]) mbx_ms;
  event sco_next;
  
  logic [31:0] Data_ds; //golden data from the driver
  logic [31:0] Data_ms; //data that we receaved serialy from the DUT
  
  function new(mailbox #(logic [31:0]) mbx_ds, mailbox #(logic [31:0]) mbx_ms);
    this.mbx_ds = mbx_ds;
    this.mbx_ms = mbx_ms;
  endfunction
  
  task main();
    mbx_ds.get(Data_ds);
    mbx_ms.get(Data_ms);
    
    $display("[%0t]:[SCO] -> Data from DRV = %0h, Data from MON = %0h.", $time(), Data_ds, Data_ms);
    
    if(Data_ds == Data_ms)
      $display("[%0t]:[SCO] -> DATA MATCHED", $time());
    else
      $display("[%0t]:[SCO] -> DATA MISMATCHED", $time());
    
    $display("------------------------------------");
    
    ->sco_next;
  endtask
  
endclass



class environment;
  
  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;
  
  event next_gd; //generator - driver event
  event next_gs; //generator - scorebaord event
  
  mailbox #(transaction) mbx_gd; //generator - driver mailbox
  mailbox #(logic [31:0]) mbx_ds; //driver - scoreboard mailbox
  mailbox #(logic [31:0]) mbx_ms; //monitor - scoreboard mailbox
  
  virtual SerialTranceiver_itf itf;
  
  function new(virtual SerialTranceiver_itf itf);
    
    mbx_gd = new();
    mbx_ds = new();
    mbx_ms = new();
                 
    gen = new(mbx_gd);
    drv = new(mbx_gd, mbx_ds);
    mon = new(mbx_ms);
    sco = new(mbx_ds, mbx_ms);
    
    this.itf = itf;
    drv.itf = itf;
    mon.itf = itf;
    
    gen.drv_next = next_gd;
    drv.drv_next = next_gd;
    gen.sco_next = next_gs;
    sco.sco_next = next_gs;
                 
  endfunction
  
  task pre_test();
    drv.reset();
  endtask
 
  task test();
  fork
    gen.main();
    drv.main();
    mon.main();
    sco.main();
  join_any
  endtask
 
  task post_test();
    wait(gen.done.triggered);
    $finish();
  endtask
  
  task main();
    pre_test();
    test();
    post_test();
  endtask
  
endclass



module SerialTranceiver_tb();
  
  SerialTranceiver_itf itf();
  environment env;
  
  SerialTranceiver DUT(
    .DataIn(itf.DataIn),
    .Sample(itf.Sample),
    .StartTx(itf.StartTx),
    .Reset(itf.Reset),
    .Clk(itf.Clk),
    .ClkTx(itf.ClkTx),
    .TxDone(itf.TxDone),
    .TxBusy(itf.TxBusy),
    .Dout(itf.Dout)
  );
  
  initial begin
    itf.Clk <= 1'b0;
    itf.ClkTx <= 1'b0;
  end
  
  always #5 itf.Clk <= ~itf.Clk;
  always #20 itf.ClkTx <= ~itf.ClkTx;
  
  initial begin
    env = new(itf);
    env.gen.count = 1;
    env.main();
  end
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end
  
endmodule
