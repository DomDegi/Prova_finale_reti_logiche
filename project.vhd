library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity project_reti_logiche is
    port (
        i_clk      : in  std_logic;
        i_rst      : in  std_logic;
        i_start     : in  std_logic;
        i_add      : in  std_logic_vector(15 downto 0);

        o_done     : out std_logic;
        o_mem_addr : out std_logic_vector(15 downto 0);
        i_mem_data : in  std_logic_vector(7 downto 0);
        o_mem_data : out std_logic_vector(7 downto 0);
        o_mem_we   : out std_logic;
        o_mem_en   : out std_logic
    );
end project_reti_logiche;

architecture rtl of project_reti_logiche is

    constant HEADER_BYTES_I : integer := 17; 
    
    -- Header
    signal k1        : std_logic_vector(7 downto 0) := (others=>'0');
    signal k2        : std_logic_vector(7 downto 0) := (others=>'0');
    signal s         : std_logic_vector(7 downto 0) := (others=>'0');
    type coeff_vec_t is array (0 to 13) of std_logic_vector(7 downto 0);
    signal c_bytes   : coeff_vec_t := (others=>(others=>'0'));

    signal K                 : integer range 0 to 65535 := 0;

    -- Header control
    signal header_count      : integer range 0 to 16 := 0; 
    signal mem_regi          : std_logic_vector(7 downto 0) := (others=>'0');
    signal first_read        : std_logic := '0';
    signal header_count2  : integer range 0 to 16 := 0;
    signal header_count3 : integer range 0 to 16 := 0; 

    type window7_t is array(0 to 6) of signed(7 downto 0);
    signal x_window          : window7_t := (others=>(others=>'0'));

    signal payload_counter   : integer range 0 to 65535 := 0;
    
    signal window_counter          : integer range 0 to 65535 := 0;
    signal address_reg    : std_logic_vector(15 downto 0) := (others=>'0');
    signal wait_counter        : integer range 0 to 1 := 0;

    -- Coefficienti selezionati
    type coeff7_t is array (0 to 6) of signed(7 downto 0);
    signal coeffs_sel        : coeff7_t := (others=>(others=>'0'));

    signal out_result        : std_logic_vector(7 downto 0) := (others=>'0');
    type state_t is (WAIT_START, BUS_HANDOVER ,READ_HEADER, RUN_READ, RUN_SHIFT, DONE);
    signal state : state_t := WAIT_START;

    signal start2, start3, start_pulse : std_logic := '0';
    signal add_base_reg : std_logic_vector(15 downto 0) := (others=>'0');

    function add_base_plus(offset : integer) return std_logic_vector is
        variable base_i : integer;
    begin
        base_i := to_integer(unsigned(add_base_reg));
        return std_logic_vector(to_unsigned(base_i + offset, 16));
    end function;
    
 
 
    function shift(val : signed; m : natural) return signed is
        variable t : signed(val'range);
    begin
        t := shift_right(val, m);
        if t(t'high) = '1' then
            t := t + 1;
        end if;
        return t;
    end function;

begin

    K <= (to_integer(unsigned(k1)) * 256) + to_integer(unsigned(k2));
    coeffs_sel(0) <= to_signed(0,8)           when s(0)='0' else signed(c_bytes(7));
    coeffs_sel(1) <= signed(c_bytes(1))       when s(0)='0' else signed(c_bytes(8));
    coeffs_sel(2) <= signed(c_bytes(2))       when s(0)='0' else signed(c_bytes(9));
    coeffs_sel(3) <= signed(c_bytes(3))       when s(0)='0' else signed(c_bytes(10));
    coeffs_sel(4) <= signed(c_bytes(4))       when s(0)='0' else signed(c_bytes(11));
    coeffs_sel(5) <= signed(c_bytes(5))       when s(0)='0' else signed(c_bytes(12));
    coeffs_sel(6) <= to_signed(0,8)           when s(0)='0' else signed(c_bytes(13));

    o_mem_en <= '1' when (state = READ_HEADER or state = RUN_READ or state = RUN_SHIFT) else '0';
    o_mem_we <= '1' when (state = RUN_SHIFT and (window_counter > 4) and (window_counter <= K+4)) else '0';
    o_mem_data <= out_result;
    o_mem_addr <=
        add_base_plus(header_count)                                            when state = READ_HEADER else
        address_reg                                                            when (state = RUN_READ) else
        add_base_plus(HEADER_BYTES_I + K + (window_counter - 5))                    when (state = RUN_SHIFT and (window_counter >= 3) and (window_counter <= K+4)) else
        (others => '0');

    o_done <= '1' when state = DONE else '0';

    process(i_clk, i_rst)
        variable x0,x1,x2,x3,x4,x5,x6 : signed(7 downto 0);
        variable prod0, prod1, prod2, prod3, prod4, prod5, prod6 : signed(15 downto 0);
        variable mac_accum   : signed(19 downto 0);
        variable sat_result      : signed(7 downto 0);
        variable norm_val  : signed(19 downto 0);
        variable t0, t1, t2, t3 : signed(19 downto 0);
    begin
        if i_rst = '1' then
            state            <= WAIT_START;

            header_count     <= 0;
            k1               <= (others=>'0');
            k2               <= (others=>'0');
            s                <= (others=>'0');
            c_bytes          <= (others=>(others=>'0'));

            mem_regi         <= (others=>'0');
            first_read       <= '0';

            x_window         <= (others=>(others=>'0'));
            payload_counter   <= 0;
            window_counter        <= 0;

            out_result       <= (others=>'0');

            address_reg     <= (others=>'0');
            wait_counter        <= 0;

            start2          <= '0';
            start3         <= '0';
            start_pulse      <= '0';
            add_base_reg     <= (others=>'0');

        elsif rising_edge(i_clk) then

            start2     <= i_start;
            start3    <= start2;
            start_pulse <= start2 and not start3;

            if start_pulse = '1' then
                add_base_reg <= i_add;
            end if;

            mem_regi        <= i_mem_data;
            header_count2  <= header_count;
            header_count3 <= header_count2;

            case state is
                when WAIT_START =>
                    if start_pulse = '1' then
                        header_count <= 0;  
                        first_read   <= '0';
                        state        <= BUS_HANDOVER;
                    end if;

                when READ_HEADER =>
                    if first_read = '0' then
                        first_read   <= '1';
                        header_count <= 0; 
                    else
                        case header_count3 is 
                            when 0  => k1           <= mem_regi;
                            when 1  => k2           <= mem_regi;
                            when 2  => s            <= mem_regi;
                            when 3  => c_bytes(0)   <= mem_regi;
                            when 4  => c_bytes(1)   <= mem_regi;
                            when 5  => c_bytes(2)   <= mem_regi;
                            when 6  => c_bytes(3)   <= mem_regi;
                            when 7  => c_bytes(4)   <= mem_regi;
                            when 8  => c_bytes(5)   <= mem_regi;
                            when 9  => c_bytes(6)   <= mem_regi;
                            when 10 => c_bytes(7)   <= mem_regi;
                            when 11 => c_bytes(8)   <= mem_regi;
                            when 12 => c_bytes(9)   <= mem_regi;
                            when 13 => c_bytes(10)  <= mem_regi;
                            when 14 => c_bytes(11)  <= mem_regi;
                            when 15 => c_bytes(12)  <= mem_regi;
                            when 16 => c_bytes(13)  <= mem_regi;
                            when others => null;
                        end case;

                        if header_count < HEADER_BYTES_I-1 then
                            header_count <= header_count + 1;
                        else
                            header_count <= header_count;
                        end if;

                        if header_count3 = HEADER_BYTES_I-1 then
                            payload_counter <= 0;
                            window_counter      <= 0;
                            wait_counter      <= 0;
                            state          <= RUN_READ;
                        end if;
                    end if;


                when BUS_HANDOVER =>
                    header_count <= 0;
                    state        <= READ_HEADER;


                when RUN_READ =>
                    if (wait_counter= 0) then
                        if payload_counter < K then
                            address_reg   <= add_base_plus(HEADER_BYTES_I + payload_counter);
                            payload_counter <= payload_counter + 1;  
                        else
                            address_reg   <= (others=>'0');     
                        end if;
                        wait_counter<= 1;
                    else
                        wait_counter<= 0;
                        state    <= RUN_SHIFT;
                    end if;


                when RUN_SHIFT =>
                    x0 := x_window(1);
                    x1 := x_window(2);
                    x2 := x_window(3);
                    x3 := x_window(4);
                    x4 := x_window(5);
                    x5 := x_window(6);

                    if window_counter <= K then
                        x6 := signed(mem_regi);
                    else
                        x6 := (others=>'0');
                    end if;

                    x_window <= (x0, x1, x2, x3, x4, x5, x6);
                    if window_counter <= 3 then
                        out_result <= (others => '0');
                        if window_counter < (K + 4) then
                            window_counter <= window_counter + 1;
                        end if;
                        if window_counter = (K + 4) then
                            state <= DONE;
                        else
                            state <= RUN_READ;
                        end if;
                    else
                        prod0 := x0 * coeffs_sel(0);
                        prod1 := x1 * coeffs_sel(1);
                        prod2 := x2 * coeffs_sel(2);
                        prod3 := x3 * coeffs_sel(3);
                        prod4 := x4 * coeffs_sel(4);
                        prod5 := x5 * coeffs_sel(5);
                        prod6 := x6 * coeffs_sel(6);
                        mac_accum := resize(prod0, 20) +
                                   resize(prod1, 20) +
                                   resize(prod2, 20) +
                                   resize(prod3, 20) +
                                   resize(prod4, 20) +
                                   resize(prod5, 20) +
                                   resize(prod6, 20);
                        -- NORMALIZATION:
                        if s(0) = '0' then
                            -- order-3
                            t0 := shift(mac_accum, 4);
                            t1 := shift(mac_accum, 6);  
                            t2 := shift(mac_accum, 8);
                            t3 := shift(mac_accum,10);
                            norm_val := resize(t0, norm_val'length) +
                                      resize(t1, norm_val'length) +
                                      resize(t2, norm_val'length) +
                                      resize(t3, norm_val'length);
                        else
                            -- order-5
                            t0 := shift(mac_accum, 6); 
                            t1 := shift(mac_accum,10); 
                            norm_val := resize(t0, norm_val'length) +
                                      resize(t1, norm_val'length);
                        end if;

                        -- SATURATION
                        if norm_val > to_signed(127, norm_val'length) then
                            sat_result := to_signed(127, 8);
                        elsif norm_val < to_signed(-128, norm_val'length) then
                            sat_result := to_signed(-128, 8);
                        else
                            sat_result := resize(norm_val, 8);
                        end if;

                        out_result <= std_logic_vector(sat_result);

                        if window_counter < (K + 4) then
                            window_counter <= window_counter + 1;
                        end if;

                        if window_counter = (K + 4) then
                            state <= DONE;
                        else
                            state <= RUN_READ;
                        end if;
                    end if;

                
                when DONE =>
                    if i_start = '0' then
                        state <= WAIT_START;
                    end if;
            end case;
        end if;
    end process;
end rtl;
