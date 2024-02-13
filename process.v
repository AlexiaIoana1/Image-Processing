`timescale 1ns / 1ps

module process(
			input clk, // clock
			input [23:0] in_pix, // valoarea pixelului de pe pozitia [in_row, in_col] din imaginea de intrare (R 23:16; G 15:8; B 7:0)
			output reg[5:0] row, col, // selecteaza un rand si o coloana din imagine
			output reg out_we, // activeaza scrierea pentru imaginea de iesire (write enable)
			output reg[23:0] out_pix, // valoarea pixelului care va fi scrisa in imaginea de iesire pe pozitia [out_row, out_col] (R 23:16; G 15:8; B 7:0)
			output reg mirror_done, // semnaleaza terminarea actiunii de oglindire (activ pe 1)
			output reg gray_done, // semnaleaza terminarea actiunii de transformare in grayscale (activ pe 1)
			output reg filter_done // semnaleaza terminarea actiunii de aplicare a filtrului de sharpness (activ pe 1)
); 

		/*
		Pentru a face operatia de oglindire (mirror):
		- citim o coloana intreaga: la fiecare tick ascendent de ceas, ne mutam la pozitia (a, b) si citim pixelul P[a][b]
		- scriem acea coloana: la fiecare tick ascendent de ceas, ne mutam la poztia (63-a, b) si scriem pixelul P[a][b]
		- ne mutam la urmatorea coloana
		- dupa ce ne-am mutat de 63 ori, am parcurs astfel toate coloanele, deci am terminat de oglindit

		Pentru a face grayscale:
		- citim imaginea pixel cu pixel, iterand pe toate liniile si coloanele top -> down si left -> right
		- pentru pixelul curent, compus din 3 bytes, calculam si scriem valoarea sa finala (nu necesita informatie in plus)

		Pentru a aplica filterul de sharpness:
		- citim imaginea pixel cu pixel, linie cu linie (liniile top->down, pentru fiecare linie ii citim coloanele left -> right)
		- mentinem ultimele 3 linii citite
		- cum am citit o linie, calculam produsul pentru linia anterioara
		- avem o stare separata pentru matricele 3x3 centrate in ultima linie. Vor calcula in mod similar
		*/

			`define MIRROR_INIT               0 // starile acestui FSM
			`define MIRROR_READ_COLUMN        1
			`define MIRROR_WRITE              2
			`define MIRROR_INCREMENT_COL      3
			`define MIRROR_DONE               4
			`define GRAY_INIT                 5
			`define GRAY_READ_AND_WRITE       6
			`define GRAY_MOVE_TO_NEXT_PIXEL 	 7
			`define GRAY_DONE                 8
			`define FILTER_INIT               9
			`define FILTER_READ_3_LINES       10
			`define FILTER_COMPUTE_FIRST_LINE 11
			`define FILTER_WRITE_FIRST_LINE   12
			`define FILTER_READ_LINE          13
			`define FILTER_UPDATE_CACHE_A     14
			`define FILTER_UPDATE_CACHE_B     15
			`define FILTER_COMPUTE_LINE       16
			`define FILTER_WRITE_LINE         17
			`define FILTER_COMPUTE_LAST_LINE  18
			`define FILTER_WRITE_LAST_LINE    19
			`define FILTER_DONE               20
 
			reg [4:0] stare_curenta = `MIRROR_INIT, stare_viitoare;
			reg [5:0] i = 0, j = 0; // sursa de adevar pentru (randul curent, coloana curenta)

			always @(posedge clk) begin // bloc secvential, updatam starea curenta doar pe partea ascendenta a ceasului
				stare_curenta <= stare_viitoare;
				row <= i;
				col <= j;
			end

			reg [7:0] min_gray = 0, max_gray = 0; // folosit la grayscale
			reg [23:0] line_1 [0:63]; // folosit la sharpness filter; linia cu 2 pozitii mai sus, cat si la oglindire (= ultima coloana citita)
			reg [23:0] line_2 [0:63]; // linia de mai sus
			reg [23:0] line_3 [0:63]; // linia curenta
			reg [23:0] line_4 [0:63]; // linie auxiliara
			reg [23:0] line_5 [0:63]; // linie auxiliara
			reg [23:0] line_6 [0:63]; // linie auxiliara
			reg [15:0] current, mid, ss, ms, ds, sm, dm, sj, mj, dj; // pixelii inconjuratori celui curent; large size for overflows

			always @(*) begin // bloc combinational, la orice modificare de semnal
							out_we = 0;
							out_pix = 0;
							mirror_done = 0;
							gray_done = 0;
							filter_done = 0;

				case(stare_curenta)
				
						`MIRROR_INIT: begin
								i = 0;
								j = 0;

								stare_viitoare = `MIRROR_READ_COLUMN;
						end

						`MIRROR_READ_COLUMN: begin
								line_1[row] = in_pix; // in_pix are fix valoarea Imagine[row][coloana curenta == col == j]

								i = (row == 63) ? 63 : row+1;

								stare_viitoare = (row == 63) ? `MIRROR_WRITE : `MIRROR_READ_COLUMN;
						end

						`MIRROR_WRITE: begin
								out_pix = line_1[63 - row]; // scriem in ordinea inversa
								out_we = 1;

								i = row - 1; // la fiecare tick de ceas (partea ascendenta), vom scadea row cu 1

								stare_viitoare = (row == 0) ? `MIRROR_INCREMENT_COL : `MIRROR_WRITE;
						end

						`MIRROR_INCREMENT_COL: begin // nu este nevoie sa setam line_1 cu zerouri, fiindca oricum o vom suprascrie
								j = col + 1;
								i = 0;

								stare_viitoare = (col == 63) ? `MIRROR_DONE : `MIRROR_READ_COLUMN;
						end

						`MIRROR_DONE: begin
								mirror_done = 1;

								stare_viitoare = `GRAY_INIT;
						end

						`GRAY_INIT: begin
								i = 0; // setand acum (i,j)=(0,0), la urmatoarea tranzitie ascendenta de ceas (row, col) va deveni (0, 0)
								j = 0;

								stare_viitoare = `GRAY_READ_AND_WRITE;
						end

						`GRAY_READ_AND_WRITE: begin
								if (in_pix[23:16] > in_pix[15:8]) begin // avem de ales intre primul si al treilea byte
								max_gray = (in_pix[23:16] > in_pix[7:0]) ? in_pix[23:16] : in_pix[7:0];
								end else begin // avem de ales intre al doilea si al treilea byte
								max_gray = (in_pix[15:8] > in_pix[7:0]) ? in_pix[15:8] : in_pix[7:0];
								end

								if (in_pix[23:16] < in_pix[15:8]) begin // avem de ales intre primul si al treilea byte
								min_gray = (in_pix[23:16] < in_pix[7:0]) ? in_pix[23:16] : in_pix[7:0];
								end else begin // avem de ales intre al doilea si al treilea byte
								min_gray = (in_pix[15:8] < in_pix[7:0]) ? in_pix[15:8] : in_pix[7:0];
								end

								out_pix[15:8] = (max_gray + min_gray) / 2; // canalul 'G' va avea valoarea grayscale
								out_pix[23:16] = 0; // canalele 'R' si 'B' devin zero
								out_pix[7:0] = 0;
								out_we = 1;

								stare_viitoare = `GRAY_MOVE_TO_NEXT_PIXEL;
						end

						`GRAY_MOVE_TO_NEXT_PIXEL: begin
								j = col + 1;
								if (col == 63) begin
								i = row + 1;
								j = 0;
								end

								stare_viitoare = (row == 63 && col == 63) ? `GRAY_DONE : `GRAY_READ_AND_WRITE;
						end

						`GRAY_DONE: begin
								gray_done = 1;

								stare_viitoare = `FILTER_INIT;
						end
						
						`FILTER_INIT: begin
								i = 0;
								j = 0;
								row = 0;
								col = 0;
								
								stare_viitoare = `FILTER_READ_3_LINES;
					  end

					`FILTER_READ_3_LINES: begin
								if (row == 0) line_1[col] = in_pix;
								if (row == 1) line_2[col] = in_pix;
								if (row == 2) line_3[col] = in_pix;

								if (col == 63) begin
								i = (row == 2) ? 0 : row + 1; // mergem la prima linie
								end

								j = (col == 63) ? 0 : col + 1;

								stare_viitoare = (col == 63 && row == 2) ? `FILTER_COMPUTE_FIRST_LINE : `FILTER_READ_3_LINES;
						end

					`FILTER_COMPUTE_FIRST_LINE: begin // calculam matricea 3x3 cu centrul in (0, col)
								ss = 0;
								ms = 0;
								ds = 0;
								sm = (col > 0) ? line_1[col-1][15:8] : 0;
								mid = line_1[col][15:8];
								dm = (col < 63) ? line_1[col+1][15:8] : 0;
								sj = (col > 0) ? line_2[col-1][15:8] : 0;
								mj = line_2[col][15:8];
								dj = (col < 63) ? line_2[col+1][15:8] : 0;

								current = 9 * mid - ss - ms - ds - sm - dm - sj - mj - dj;

								stare_viitoare = `FILTER_WRITE_FIRST_LINE;
						end

						`FILTER_WRITE_FIRST_LINE: begin
								row = i;
								col = j;

								out_pix[23:16] = 0;
								out_pix[7:0] = 0;

								if (current > 255) begin
												out_pix[15:8] = 255;
											end else begin
								out_pix[15:8] = current[7:0];
											end

								out_we = 1;

								if (col == 63) i = 1;
								j = (col==63) ? 0 : col + 1;

								stare_viitoare = (j == 63) ? `FILTER_COMPUTE_LINE : `FILTER_COMPUTE_FIRST_LINE;
						end

						`FILTER_READ_LINE: begin
								line_4[col] = in_pix;

								if (col == 63) begin // am terminat de citit linia, mergem sa o calculam
								stare_viitoare = `FILTER_UPDATE_CACHE_A;
								end else begin
								j = col + 1;

								stare_viitoare = `FILTER_READ_LINE;
								end
						end

						`FILTER_COMPUTE_LINE: begin
								//  calculam matricea 3x3 cu centrul in (row, col), centrul fiind cache-uit in line_2
								ss = (col > 0) ? line_1[col-1][15:8] : 0;
								ms = line_1[col][15:8];
								ds = (col < 63) ? line_1[col+1][15:8] : 0;
								sm = (col > 0) ? line_2[col-1][15:8] : 0;
								mid = line_2[col][15:8];
								dm = (col < 63) ? line_2[col+1][15:8] : 0;
								sj = (col > 0) ? line_3[col-1][15:8] : 0;
								mj = line_3[col][15:8];
								dj = (col < 63) ? line_3[col+1][15:8] : 0;

								current = 9 * mid - ss - ms - ds - sm - dm - sj - mj - dj;

								stare_viitoare = `FILTER_WRITE_LINE;
						end

						`FILTER_WRITE_LINE: begin
								row = i;
								col = j;
								out_pix[23:16] = 0;
								out_pix[7:0] = 0;

								if (current > 255) begin
												out_pix[15:8] = 255;
											end else begin
								out_pix[15:8] = current[7:0];
											end

								out_we = 1;

								if (col == 63) begin
								j = 0;
								i = (row == 63) ? 63 : row + 2; // deja am citit urmatoarea linie, o vom citi pe prima necitita; cand terminam mergem la ultima linie
								end else j = col + 1;

								if (row == 63 && col == 63) begin
								stare_viitoare = `FILTER_COMPUTE_LAST_LINE;
								end else begin
								stare_viitoare = (col == 63) ? `FILTER_READ_LINE : `FILTER_COMPUTE_LINE;
								end
						end

						`FILTER_UPDATE_CACHE_A: begin // copiem liniile de cache (2, 3, 4) in liniile (6, 5, 4)
								// updatam liniile de cache <= line_4 este doar un intermediar care stocheaza linia curenta
								for (min_gray = 0; min_gray <= 63; min_gray = min_gray + 1) begin // refolosim registrul min_gray
								line_6[min_gray] = line_2[min_gray];
								line_5[min_gray] = line_3[min_gray];
								// line_4[min_gray] = line_4[min_gray]; // operatie care nu face nimic, dar exprima clar intentia algoritmului
								end

								stare_viitoare = `FILTER_UPDATE_CACHE_B;
						end

						`FILTER_UPDATE_CACHE_B: begin // copiem liniile de cache (6, 5, 4) in liniile (1, 2, 3)
								for (min_gray = 0; min_gray <= 63; min_gray = min_gray + 1) begin // refolosim registrul min_gray
								line_1[min_gray] = line_6[min_gray];
								line_2[min_gray] = line_5[min_gray];
								line_3[min_gray] = line_4[min_gray];
								end

								i = row-1; // ne pozitionam pe linia anterioara, ca sa filtram pentru matricele 3x3 cu centrul in ea
								j = 0;

								stare_viitoare = `FILTER_COMPUTE_LINE;
						end // dupa starile `FILTER_READ_LINE -> `FILTER_UPDATE_CACHE_A -> `FILTER_UPDATE_CACHE_B -> `FILTER_READ_LINE, am copiat (2,3,4) -> (1,2,3)

						`FILTER_COMPUTE_LAST_LINE: begin
								// calculam matricele 3x3 cu centru pe ultima linie
								ss = (col > 0) ? line_2[col-1][15:8] : 0;
								ms = line_2[col][15:8];
								ds = (col < 63) ? line_2[col+1][15:8] : 0;
								sm = (col > 0) ? line_3[col-1][15:8] : 0;
								mid = line_3[col][15:8] ;
								dm = (col < 63) ? line_3[col+1][15:8] : 0;
								sj = 0;
								mj = 0;
								dj = 0;

								current = 9 * mid - ss - ms - ds - sm - dm - sj - mj - dj;
								
								stare_viitoare = `FILTER_WRITE_LAST_LINE;
						end

						`FILTER_WRITE_LAST_LINE: begin
								row = i;
								col = j;

								out_pix[23:16] = 0;
								out_pix[7:0] = 0;

								if (current > 255) begin
												out_pix[15:8] = 255;
											end else begin
								out_pix[15:8] = current[7:0];
											end

								out_we = 1;

								j = col + 1;

								stare_viitoare = (col == 63) ? `FILTER_DONE : `FILTER_COMPUTE_LAST_LINE;
						end

						`FILTER_DONE: begin
								filter_done = 1;

								stare_viitoare = `MIRROR_INIT;
						end

				endcase
		end

endmodule