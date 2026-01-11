`timescale 1ns/1ps

module tb_carrier_mixer;

  // DUT inputs
  logic if_sign;
  logic if_mag;
  logic carrier_sign;
  logic carrier_mag;

  // DUT outputs
  logic       mix_sign;
  logic [2:0] mix_mag;

  // DUT instance
  carrier_mixer dut (
    .if_sign      (if_sign),
    .if_mag       (if_mag),
    .carrier_sign (carrier_sign),
    .carrier_mag  (carrier_mag),
    .mix_sign     (mix_sign),
    .mix_mag      (mix_mag)
  );

  // Optional helpers: decode IF/carrier values for console display
  function automatic int decode_if_value(input logic s, input logic m);
    // IF magnitude bit: 0 -> 1, 1 -> 3
    int mag;
    begin
      mag = (m == 1'b0) ? 1 : 3;
      decode_if_value = (s == 1'b1) ? mag : -mag;
    end
  endfunction

  function automatic int decode_carrier_value(input logic s, input logic m);
    // Carrier magnitude bit: 0 -> 1, 1 -> 2
    int mag;
    begin
      mag = (m == 1'b0) ? 1 : 2;
      decode_carrier_value = (s == 1'b1) ? mag : -mag;
    end
  endfunction

  function automatic int decode_mix_value(input logic s, input logic [2:0] m);
    int mag;
    begin
      mag = m; // Inplicit conversion
      decode_mix_value = (s == 1'b1) ? mag : -mag;
    end
  endfunction

  // Stimulus
  initial begin
    // VCD setup (do this once)
    $dumpfile("carrier_mixer.vcd");
    $dumpvars(0, tb_carrier_mixer);

    // Initialize
    if_sign      = 1'b0;
    if_mag       = 1'b0;
    carrier_sign = 1'b0;
    carrier_mag  = 1'b0;

    // Iterate all 16 input combinations
    for (int cs = 0; cs < 2; cs++) begin
      for (int cm = 0; cm < 2; cm++) begin
        for (int is = 0; is < 2; is++) begin
          for (int im = 0; im < 2; im++) begin
            #20;
            if_sign      = logic'(is);
            if_mag       = logic'(im);
            carrier_sign = logic'(cs);
            carrier_mag  = logic'(cm);

            // Small delay to let combinational outputs settle
            #1;

            $display("IF=%2d  CARR=%2d  -> mix_sign=%0d mix_mag=%b (%2d)",
                     decode_if_value(if_sign, if_mag),
                     decode_carrier_value(carrier_sign, carrier_mag),
                     mix_sign, mix_mag,
                     decode_mix_value(mix_sign, mix_mag));
          end
        end
      end
    end

    // Return to zeros then finish
    #20;
    if_sign      = 1'b0;
    if_mag       = 1'b0;
    carrier_sign = 1'b0;
    carrier_mag  = 1'b0;

    #20;
    $finish;
  end

endmodule
