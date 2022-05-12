CLASS lhc_Travel DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    TYPES tt_travel_update TYPE TABLE FOR UPDATE zi_travel_MARIO.

    METHODS CalculateTravelKey FOR DETERMINATION Travel~CalculateTravelKey
      IMPORTING keys FOR Travel.

*    METHODS validate_customer FOR VALIDATION Travel~validateCustomer IMPORTING keys FOR Travel.
    METHODS validate_customer FOR VALIDATE ON SAVE IMPORTING keys FOR Travel~validateCustomer.
    METHODS validate_dates FOR VALIDATION Travel~validateDates IMPORTING keys FOR Travel.
    METHODS validate_travel_status FOR VALIDATION Travel~validateStatus IMPORTING keys FOR Travel.
    METHODS set_status_completed FOR MODIFY IMPORTING keys FOR ACTION Travel~acceptTravel RESULT result.
    METHODS get_features FOR FEATURES IMPORTING keys REQUEST requested_features FOR travel RESULT result.

ENDCLASS.

CLASS lhc_Travel IMPLEMENTATION.

  METHOD CalculateTravelKey.

    SELECT FROM ztravel_MARIO
    FIELDS MAX( travel_id ) INTO @DATA(lv_max_travel_id).

    LOOP AT keys INTO DATA(ls_key).
      lv_max_travel_id = lv_max_travel_id + 1.
      MODIFY ENTITIES OF zi_travel_MARIO IN LOCAL MODE
        ENTITY Travel
          UPDATE SET FIELDS WITH VALUE #( ( mykey     = ls_key-mykey
                                            travel_id = lv_max_travel_id ) )
          REPORTED DATA(ls_reported).
      APPEND LINES OF ls_reported-travel TO reported-travel.
    ENDLOOP.

  ENDMETHOD.

  METHOD validate_customer.

    READ ENTITY zi_travel_MARIO\\travel FROM VALUE #(
        FOR <root_key> IN keys ( %key     = <root_key>
                                 %control = VALUE #( customer_id = if_abap_behv=>mk-on ) ) )
        RESULT DATA(lt_travel).

    DATA lt_customer TYPE SORTED TABLE OF /dmo/customer WITH UNIQUE KEY customer_id.

    " Optimization of DB select: extract distinct non-initial customer IDs
    lt_customer = CORRESPONDING #( lt_travel DISCARDING DUPLICATES MAPPING customer_id = customer_id EXCEPT * ).
    DELETE lt_customer WHERE customer_id IS INITIAL.
    CHECK lt_customer IS NOT INITIAL.

    " Check if customer ID exist
    SELECT FROM /dmo/customer FIELDS customer_id
      FOR ALL ENTRIES IN @lt_customer
      WHERE customer_id = @lt_customer-customer_id
      INTO TABLE @DATA(lt_customer_db).

    " Raise msg for non existing customer id
    LOOP AT lt_travel INTO DATA(ls_travel).

      IF
        ls_travel-customer_id IS NOT INITIAL AND
        NOT line_exists( lt_customer_db[ customer_id = ls_travel-customer_id ] ).
        APPEND VALUE #(  mykey = ls_travel-mykey ) TO failed-travel.
        APPEND VALUE #(  mykey = ls_travel-mykey
                         %msg  = new_message( id       = /dmo/cx_flight_legacy=>customer_unkown-msgid
                                              number   = /dmo/cx_flight_legacy=>customer_unkown-msgno
                                              v1       = ls_travel-customer_id
                                              severity = if_abap_behv_message=>severity-error )
                         %element-customer_id = if_abap_behv=>mk-on ) TO reported-travel.
      ENDIF.

    ENDLOOP.

  ENDMETHOD.

  METHOD validate_dates.

    READ ENTITY zi_travel_MARIO\\travel FROM VALUE #(
        FOR <root_key> IN keys ( %key     = <root_key>
                                 %control = VALUE #( begin_date = if_abap_behv=>mk-on
                                                     end_date   = if_abap_behv=>mk-on ) ) )
        RESULT DATA(lt_travel_result).

    LOOP AT lt_travel_result INTO DATA(ls_travel_result).

      IF ls_travel_result-end_date < ls_travel_result-begin_date.  "end_date before begin_date

        APPEND VALUE #( %key  = ls_travel_result-%key
                        mykey = ls_travel_result-mykey ) TO failed.

        APPEND VALUE #( %key  = ls_travel_result-%key
                        %msg  = new_message( id       = /dmo/cx_flight_legacy=>end_date_before_begin_date-msgid
                                             number   = /dmo/cx_flight_legacy=>end_date_before_begin_date-msgno
                                             v1       = ls_travel_result-begin_date
                                             v2       = ls_travel_result-end_date
                                             v3       = ls_travel_result-mykey
                                             severity = if_abap_behv_message=>severity-error )
                        %element-begin_date = if_abap_behv=>mk-on
                        %element-end_date   = if_abap_behv=>mk-on ) TO reported.

      ELSEIF ls_travel_result-begin_date < cl_abap_context_info=>get_system_date( ).  "begin_date must be in the future

        APPEND VALUE #( %key = ls_travel_result-%key
                        mykey = ls_travel_result-mykey ) TO failed.

        APPEND VALUE #( %key = ls_travel_result-%key
                        %msg = new_message( id       = /dmo/cx_flight_legacy=>begin_date_before_system_date-msgid
                                            number   = /dmo/cx_flight_legacy=>begin_date_before_system_date-msgno
                                            severity = if_abap_behv_message=>severity-error )
                        %element-begin_date = if_abap_behv=>mk-on
                        %element-end_date   = if_abap_behv=>mk-on ) TO reported.
      ENDIF.

    ENDLOOP.

  ENDMETHOD.

  METHOD validate_travel_status.

    READ ENTITY zi_travel_MARIO\\travel FROM VALUE #(
      FOR <root_key> IN keys ( %key     = <root_key>
                               %control = VALUE #( overall_status = if_abap_behv=>mk-on ) ) )
      RESULT DATA(lt_travel_result).

    LOOP AT lt_travel_result INTO DATA(ls_travel_result).

      CASE ls_travel_result-overall_status.
        WHEN 'O'.  " Open
        WHEN 'X'.  " Cancelled or rejected
        WHEN 'A'.  " Accepted

        WHEN OTHERS.
          APPEND VALUE #( %key = ls_travel_result-%key ) TO failed.

          APPEND VALUE #( %key = ls_travel_result-%key
                          %msg = new_message( id       = /dmo/cx_flight_legacy=>status_is_not_valid-msgid
                                              number   = /dmo/cx_flight_legacy=>status_is_not_valid-msgno
                                              v1       = ls_travel_result-overall_status
                                              severity = if_abap_behv_message=>severity-error )
                          %element-overall_status = if_abap_behv=>mk-on ) TO reported.
      ENDCASE.

    ENDLOOP.

  ENDMETHOD.

  METHOD set_status_completed.

    " Modify in local mode: BO-related updates that are not relevant for authorization checks
    MODIFY ENTITIES OF zi_travel_MARIO IN LOCAL MODE
           ENTITY travel
              UPDATE FROM VALUE #( FOR key IN keys ( mykey = key-mykey
                                                     overall_status = 'A' " Accepted
                                                     %control-overall_status = if_abap_behv=>mk-on ) )
           FAILED   failed
           REPORTED reported.

    " Read changed data for action result
    READ ENTITIES OF zi_travel_MARIO IN LOCAL MODE
         ENTITY travel
         FROM VALUE #( FOR key IN keys (  mykey = key-mykey
                                          %control = VALUE #(
                                            travel_id       = if_abap_behv=>mk-on
                                            agency_id       = if_abap_behv=>mk-on
                                            customer_id     = if_abap_behv=>mk-on
                                            begin_date      = if_abap_behv=>mk-on
                                            end_date        = if_abap_behv=>mk-on
                                            booking_fee     = if_abap_behv=>mk-on
                                            total_price     = if_abap_behv=>mk-on
                                            currency_code   = if_abap_behv=>mk-on
                                            overall_status  = if_abap_behv=>mk-on
                                            description     = if_abap_behv=>mk-on
                                            created_by      = if_abap_behv=>mk-on
                                            created_at      = if_abap_behv=>mk-on
                                            last_changed_by = if_abap_behv=>mk-on
                                            last_changed_at = if_abap_behv=>mk-on
                                          ) ) )
         RESULT DATA(lt_travel).

    result = VALUE #( FOR travel IN lt_travel ( mykey = travel-mykey
                                                %param    = travel
                                              ) ).

  ENDMETHOD.

  METHOD get_features.

    READ ENTITY zi_travel_MARIO FROM VALUE #( FOR keyval IN keys
                                                      (  %key = keyval-%key
                                                         %control-mykey = if_abap_behv=>mk-on
                                                         %control-overall_status = if_abap_behv=>mk-on ) )
                                RESULT DATA(lt_travel_result).


    result = VALUE #( FOR ls_travel IN lt_travel_result
                       ( %key = ls_travel-%key
                         %features-%action-acceptTravel = COND #( WHEN ls_travel-overall_status = 'A'
                                                                    THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled   )
                      ) ).

  ENDMETHOD.

ENDCLASS.
