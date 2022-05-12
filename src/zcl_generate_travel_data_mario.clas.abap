CLASS zcl_generate_travel_data_MARIO DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS ZCL_GENERATE_TRAVEL_DATA_MARIO IMPLEMENTATION.


  METHOD if_oo_adt_classrun~main.
    DATA:itab TYPE TABLE OF ztravel_MARIO.

*   read current timestamp
    GET TIME STAMP FIELD DATA(zv_tsl).

*   fill internal travel table (itab)
    itab = VALUE #(
  ( travel_id = '00000001' agency_id = '070010' customer_id = '000011' begin_date = '20200310' end_date = '20200317' booking_fee = '17.00' total_price = '800.00' currency_code = 'EUR'
    description = 'Need a break!' overall_status = 'O' created_by = 'CB0000000007' created_at = '20200310105654.4296640' last_changed_by = 'CB0000000007' last_changed_at = '20200310111041.2251330' )
 ).

*   delete existing entries in the database table
    DELETE FROM ztravel_MARIO.

*   insert the new table entries
    INSERT ztravel_MARIO FROM TABLE @itab.

*   check the result
    SELECT * FROM ztravel_MARIO INTO TABLE @itab.
    out->write( sy-dbcnt ).
    out->write( 'Travel data inserted successfully!').

  ENDMETHOD.
ENDCLASS.
