REPORT zclean_core_successors.

DATA gv_field TYPE fieldname.

PARAMETERS: p_tab  RADIOBUTTON GROUP what DEFAULT 'X' USER-COMMAND what MODIF ID wht,
            p_obj  RADIOBUTTON GROUP what MODIF ID wht.
SELECTION-SCREEN SKIP.
PARAMETERS: p_alv  RADIOBUTTON GROUP out DEFAULT 'X' USER-COMMAND mode,
            p_json RADIOBUTTON GROUP out.
SELECTION-SCREEN SKIP.
PARAMETERS p_table TYPE tabname MODIF ID tab.
SELECT-OPTIONS s_field FOR gv_field NO INTERVALS MODIF ID tab.
PARAMETERS: p_cds   TYPE ddlname MODIF ID tab,
            p_oname TYPE c LENGTH 40 MODIF ID obj,
            p_otype TYPE c LENGTH 10 MODIF ID obj.

CLASS lcl_report DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS run.

    METHODS object_type_help.

  PRIVATE SECTION.
    TYPES: BEGIN OF ts_row,
             table_name  TYPE tabname,
             table_field TYPE fieldname,
             cds_view    TYPE ddlname,
             cds_field   TYPE fieldname,
             match_type  TYPE c LENGTH 13,
             how_to_use  TYPE c LENGTH 10,
             release     TYPE c LENGTH 12,
             covered     TYPE i,
             expression  TYPE string,
             defined_in  TYPE string,
           END OF ts_row,
           tt_row   TYPE STANDARD TABLE OF ts_row WITH EMPTY KEY,
           tt_field TYPE STANDARD TABLE OF fieldname WITH EMPTY KEY.

    TYPES: BEGIN OF ts_key,
             position     TYPE i,
             field_name   TYPE fieldname,
             data_element TYPE rollname,
             description  TYPE as4text,
             data_type    TYPE datatype_d,
             length       TYPE ddleng,
           END OF ts_key,
           tt_key TYPE STANDARD TABLE OF ts_key WITH EMPTY KEY.

    TYPES: BEGIN OF ts_successor,
             object_type    TYPE c LENGTH 10,
             object_name    TYPE string,
             object_state   TYPE c LENGTH 30,
             successor_type TYPE c LENGTH 10,
             successor_name TYPE string,
             abap_cloud     TYPE c LENGTH 13,
           END OF ts_successor,
           tt_successor TYPE STANDARD TABLE OF ts_successor WITH EMPTY KEY.

    TYPES: BEGIN OF ts_api_key,
             object_type     TYPE ars_w_api_state-object_type,
             object_id       TYPE ars_w_api_state-object_id,
             sub_object_name TYPE ars_w_api_state-sub_object_name,
           END OF ts_api_key,
           tt_api_key TYPE SORTED TABLE OF ts_api_key WITH UNIQUE KEY object_type object_id sub_object_name.

    TYPES: BEGIN OF ts_api_state,
             object_type     TYPE ars_w_api_state-object_type,
             object_id       TYPE ars_w_api_state-object_id,
             sub_object_name TYPE ars_w_api_state-sub_object_name,
             release_state   TYPE ars_w_api_state-release_state,
             cloud           TYPE ars_w_api_state-use_in_sap_cloud_platform,
           END OF ts_api_state,
           tt_api_state TYPE SORTED TABLE OF ts_api_state
                        WITH NON-UNIQUE KEY object_type object_id sub_object_name.

    TYPES tt_name_range TYPE RANGE OF ars_w_api_sccssr-sub_object_name.

    TYPES: BEGIN OF ts_export,
             release    TYPE string,
             pairs_from TYPE string,
             tables     TYPE zcl_clean_core_successors=>tt_view_map,
             successors TYPE tt_successor,
           END OF ts_export.

    CONSTANTS: c_same_column   TYPE c LENGTH 13 VALUE 'Same column',
               c_in_expression TYPE c LENGTH 13 VALUE 'In expression',
               c_released      TYPE c LENGTH 13 VALUE 'Released',
               c_key_user_only TYPE c LENGTH 13 VALUE 'Key user only',
               c_not_released  TYPE c LENGTH 13 VALUE 'Not released'.

    DATA mt_rows       TYPE tt_row.
    DATA mt_keys       TYPE tt_key.
    DATA mt_successors TYPE tt_successor.
    DATA mv_note       TYPE string.
    DATA mv_source     TYPE string.
    DATA mo_extractor  TYPE REF TO zcl_clean_core_successors.

    METHODS has_successor_list
      RETURNING VALUE(rv_found) TYPE abap_bool.

    METHODS all_pairs
      RETURNING VALUE(rt_pairs) TYPE zcl_clean_core_successors=>tt_pair.

    METHODS read_states
      IMPORTING it_keys          TYPE tt_api_key
      RETURNING VALUE(rt_states) TYPE tt_api_state.

    METHODS availability
      IMPORTING is_state       TYPE ts_api_state
      RETURNING VALUE(rv_text) TYPE ts_successor-abap_cloud.

    METHODS show_objects.

    METHODS read_successors
      IMPORTING it_names       TYPE tt_name_range
      RETURNING VALUE(rt_rows) TYPE tt_successor.

    METHODS explain_missing
      IMPORTING it_names TYPE tt_name_range.

    METHODS show_successors.

    METHODS system_release
      RETURNING VALUE(rv_release) TYPE string.

    METHODS selected_pairs
      RETURNING VALUE(rt_pairs) TYPE zcl_clean_core_successors=>tt_pair.

    METHODS extract_pairs
      IMPORTING it_pairs         TYPE zcl_clean_core_successors=>tt_pair
      RETURNING VALUE(rt_result) TYPE zcl_clean_core_successors=>tt_view_map.

    METHODS fill_rows
      IMPORTING it_result TYPE zcl_clean_core_successors=>tt_view_map.

    METHODS requested_fields
      RETURNING VALUE(rt_fields) TYPE tt_field.

    METHODS add_coverage
      IMPORTING it_fields TYPE tt_field.

    METHODS show_rows.

    METHODS on_link_click FOR EVENT link_click OF cl_salv_events_table
      IMPORTING row column.

    METHODS read_table_keys
      IMPORTING iv_table TYPE tabname.

    METHODS read_view_keys
      IMPORTING iv_view TYPE ddlname.

    METHODS show_keys
      IMPORTING iv_name TYPE string.

    METHODS show_definition
      IMPORTING is_row TYPE ts_row.

    METHODS highlight
      IMPORTING iv_line       TYPE string
      RETURNING VALUE(rv_html) TYPE string.

    METHODS set_heading
      IMPORTING io_columns TYPE REF TO cl_salv_columns_table
                iv_column  TYPE lvc_fname
                iv_text    TYPE scrtext_s
      RAISING   cx_salv_not_found.

    METHODS download_all.

    METHODS choose_file
      IMPORTING iv_default     TYPE string
      RETURNING VALUE(rv_file) TYPE string.

    METHODS download
      IMPORTING iv_json    TYPE string
                iv_file    TYPE string
                iv_written TYPE string.
ENDCLASS.


CLASS lcl_report IMPLEMENTATION.
  METHOD run.
    IF has_successor_list( ) = abap_false.
      MESSAGE 'This system has no SAP successor list (S/4HANA 2022 or later has one). Use the AI skill from the repository instead.'
              TYPE 'I'.
      RETURN.
    ENDIF.

    IF p_json = abap_true.
      download_all( ).
      RETURN.
    ENDIF.

    IF p_obj = abap_true.
      show_objects( ).
      RETURN.
    ENDIF.

    IF p_cds IS NOT INITIAL AND p_table IS INITIAL.
      MESSAGE 'Enter the table the CDS view replaces' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
    IF s_field[] IS NOT INITIAL AND p_table IS INITIAL.
      MESSAGE 'Enter the table the fields belong to' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    DATA(lt_pairs) = selected_pairs( ).
    IF lt_pairs IS INITIAL.
      MESSAGE |No successor CDS view listed for { p_table }. Enter one in the CDS view field.|
              TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    mo_extractor = NEW #( ).
    fill_rows( extract_pairs( lt_pairs ) ).
    show_rows( ).
  ENDMETHOD.


  METHOD download_all.
    DATA(lv_file) = choose_file( `clean-core-successors.json` ).
    IF lv_file IS INITIAL.
      RETURN.
    ENDIF.

    mo_extractor = NEW #( ).
    DATA(ls_export) = VALUE ts_export( release    = system_release( )
                                       tables     = extract_pairs( all_pairs( ) )
                                       successors = read_successors( VALUE #( ) ) ).
    ls_export-pairs_from = mv_source.

    download( iv_json    = /ui2/cl_json=>serialize( data        = ls_export
                                                    pretty_name = /ui2/cl_json=>pretty_mode-camel_case )
              iv_file    = lv_file
              iv_written = |{ lines( ls_export-tables ) } views and { lines( ls_export-successors ) } successors| ).
  ENDMETHOD.


  METHOD system_release.
    SELECT component, release, extrelease
      FROM cvers
      WHERE component IN ( 'S4CORE', 'SAP_BASIS' )
      INTO TABLE @DATA(lt_components).

    DATA(ls_component) = VALUE #( lt_components[ component = 'S4CORE' ]
                                  DEFAULT VALUE #( lt_components[ component = 'SAP_BASIS' ] OPTIONAL ) ).
    rv_release = condense( |{ ls_component-component } { ls_component-release } SP{ ls_component-extrelease ALPHA = OUT }| ).
  ENDMETHOD.


  METHOD has_successor_list.
    SELECT SINGLE @abap_true
      FROM ars_w_api_sccssr
      WHERE object_type            = 'TABL'
        AND successor_object_type  = 'DDLS'
        AND compatibility_contract = 'C1'
      INTO @rv_found.
  ENDMETHOD.


  METHOD all_pairs.
    SELECT object_id, successor_object_name
      FROM ars_w_api_sccssr
      WHERE object_type            = 'TABL'
        AND successor_object_type  = 'DDLS'
        AND compatibility_contract = 'C1'
      INTO TABLE @DATA(lt_successors).

    mv_source = `this system`.
    DATA(lt_keys) = VALUE tt_api_key( ).
    LOOP AT lt_successors INTO DATA(ls_successor).
      INSERT VALUE #( object_type     = 'DDLS'
                      object_id       = ls_successor-successor_object_name
                      sub_object_name = ls_successor-successor_object_name ) INTO TABLE lt_keys.
    ENDLOOP.
    DATA(lt_states) = read_states( lt_keys ).

    LOOP AT lt_successors INTO ls_successor.
      DATA(ls_state) = VALUE #( lt_states[ object_type     = 'DDLS'
                                           object_id       = ls_successor-successor_object_name
                                           sub_object_name = ls_successor-successor_object_name ] OPTIONAL ).
      INSERT VALUE #( table_name = ls_successor-object_id
                      cds_name   = ls_successor-successor_object_name
                      released   = xsdbool( availability( ls_state ) = c_released ) )
             INTO TABLE rt_pairs.
    ENDLOOP.
    SORT rt_pairs BY table_name cds_name.
    DELETE ADJACENT DUPLICATES FROM rt_pairs COMPARING table_name cds_name.
  ENDMETHOD.


  METHOD read_states.
    IF it_keys IS INITIAL.
      RETURN.
    ENDIF.

    SELECT state~object_type, state~object_id, state~sub_object_name,
           state~release_state,
           state~use_in_sap_cloud_platform AS cloud
      FROM @it_keys AS api_key
      INNER JOIN ars_w_api_state AS state
        ON  state~object_type     = api_key~object_type
        AND state~object_id       = api_key~object_id
        AND state~sub_object_name = api_key~sub_object_name
      WHERE state~compatibility_contract = 'C1'
      INTO CORRESPONDING FIELDS OF TABLE @rt_states.
  ENDMETHOD.


  METHOD availability.
    rv_text = COND #( WHEN is_state-release_state = 'RELEASED' AND is_state-cloud = abap_true
                        THEN c_released
                      WHEN is_state-release_state = 'RELEASED'
                        THEN c_key_user_only
                      ELSE c_not_released ).
  ENDMETHOD.


  METHOD object_type_help.
    TYPES: BEGIN OF ts_type,
             object_type TYPE char10,
             description TYPE ddtext,
           END OF ts_type.
    DATA lt_types TYPE STANDARD TABLE OF ts_type WITH EMPTY KEY.

    SELECT object_type, sub_object_type
      FROM ars_w_api_sccssr
      WHERE compatibility_contract = 'C1'
      INTO TABLE @DATA(lt_links).

    LOOP AT lt_links INTO DATA(ls_link).
      DATA(lv_type) = CONV ts_type-object_type( COND #( WHEN ls_link-sub_object_type = 'CDS_STOB'
                                                          OR ls_link-sub_object_type IS INITIAL
                                                          THEN ls_link-object_type
                                                        ELSE ls_link-sub_object_type ) ).
      INSERT VALUE #( object_type = lv_type
                      description = SWITCH #( lv_type
                                               WHEN 'FUNC'     THEN 'Function module'
                                               WHEN 'CLAS'     THEN 'Class'
                                               WHEN 'INTF'     THEN 'Interface'
                                               WHEN 'DTEL'     THEN 'Data element'
                                               WHEN 'DOMA'     THEN 'Domain'
                                               WHEN 'DDLS'     THEN 'CDS view'
                                               WHEN 'TABL'     THEN 'Table'
                                               WHEN 'TTYP'     THEN 'Table type'
                                               WHEN 'BADI_DEF' THEN 'BAdI definition'
                                               WHEN 'SUSO'     THEN 'Authorization object'
                                               WHEN 'CHKV'     THEN 'ATC check variant'
                                               WHEN 'IWSV'     THEN 'Gateway service' ) )
             INTO TABLE lt_types.
    ENDLOOP.
    SORT lt_types BY object_type.
    DELETE ADJACENT DUPLICATES FROM lt_types COMPARING object_type.

    CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
      EXPORTING
        retfield    = 'OBJECT_TYPE'
        dynpprog    = sy-repid
        dynpnr      = sy-dynnr
        dynprofield = 'P_OTYPE'
        value_org   = 'S'
      TABLES
        value_tab   = lt_types
      EXCEPTIONS
        OTHERS      = 1.
    IF sy-subrc <> 0.
      MESSAGE 'The value list could not be shown' TYPE 'S' DISPLAY LIKE 'E'.
    ENDIF.
  ENDMETHOD.


  METHOD show_objects.
    IF p_oname IS INITIAL.
      MESSAGE 'Enter an object name' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    DATA(lv_name) = to_upper( condense( p_oname ) ).
    DATA(lt_names) = VALUE tt_name_range( ( sign   = 'I'
                                            option = COND #( WHEN lv_name CA '*+' THEN 'CP' ELSE 'EQ' )
                                            low    = lv_name ) ).
    mt_successors = read_successors( lt_names ).
    IF p_otype IS NOT INITIAL.
      DELETE mt_successors WHERE object_type <> p_otype.
    ENDIF.

    IF mt_successors IS INITIAL.
      explain_missing( lt_names ).
      RETURN.
    ENDIF.
    show_successors( ).
  ENDMETHOD.


  METHOD read_successors.
    SELECT object_type, object_id, sub_object_type, sub_object_name,
           successor_object_type, successor_object_name,
           successor_sub_object_type, successor_sub_object_name
      FROM ars_w_api_sccssr
      WHERE compatibility_contract = 'C1'
        AND ( object_id IN @it_names OR sub_object_name IN @it_names )
      INTO TABLE @DATA(lt_links).
    IF lt_links IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lt_keys) = VALUE tt_api_key( ).
    LOOP AT lt_links INTO DATA(ls_link).
      INSERT VALUE #( object_type     = ls_link-object_type
                      object_id       = ls_link-object_id
                      sub_object_name = ls_link-sub_object_name ) INTO TABLE lt_keys.
      INSERT VALUE #( object_type     = ls_link-successor_object_type
                      object_id       = ls_link-successor_object_name
                      sub_object_name = ls_link-successor_sub_object_name ) INTO TABLE lt_keys.
    ENDLOOP.
    DATA(lt_states) = read_states( lt_keys ).

    LOOP AT lt_links INTO ls_link.
      DATA(ls_source) = VALUE #( lt_states[ object_type     = ls_link-object_type
                                            object_id       = ls_link-object_id
                                            sub_object_name = ls_link-sub_object_name ] OPTIONAL ).
      DATA(ls_target) = VALUE #( lt_states[ object_type     = ls_link-successor_object_type
                                            object_id       = ls_link-successor_object_name
                                            sub_object_name = ls_link-successor_sub_object_name ] OPTIONAL ).
      INSERT VALUE #( object_type    = COND #( WHEN ls_link-sub_object_type = 'CDS_STOB' OR ls_link-sub_object_type IS INITIAL
                                                 THEN ls_link-object_type
                                               ELSE ls_link-sub_object_type )
                      object_name    = COND #( WHEN ls_link-sub_object_name IS INITIAL
                                                 THEN ls_link-object_id
                                               ELSE ls_link-sub_object_name )
                      object_state   = COND #( WHEN ls_source-release_state IS INITIAL
                                                 THEN 'NO ENTRY'
                                               ELSE ls_source-release_state )
                      successor_type = COND #( WHEN ls_link-successor_sub_object_type = 'CDS_STOB'
                                                 OR ls_link-successor_sub_object_type IS INITIAL
                                                 THEN ls_link-successor_object_type
                                               ELSE ls_link-successor_sub_object_type )
                      successor_name = COND #( WHEN ls_link-successor_sub_object_name IS INITIAL
                                                 THEN ls_link-successor_object_name
                                               ELSE ls_link-successor_sub_object_name )
                      abap_cloud     = availability( ls_target ) )
             INTO TABLE rt_rows.
    ENDLOOP.
    SORT rt_rows BY object_type object_name successor_name.
  ENDMETHOD.


  METHOD explain_missing.
    SELECT release_state, use_in_sap_cloud_platform AS cloud
      FROM ars_w_api_state
      WHERE compatibility_contract = 'C1'
        AND ( object_id IN @it_names OR sub_object_name IN @it_names )
      INTO TABLE @DATA(lt_found).

    DATA(lv_name) = condense( p_oname ).
    IF line_exists( lt_found[ release_state = 'RELEASED' cloud = abap_true ] ).
      MESSAGE |{ lv_name } is released for ABAP Cloud. No successor is needed.| TYPE 'S'.
    ELSEIF lt_found IS INITIAL.
      MESSAGE |{ lv_name } is not in this system's API list, and SAP names no successor for it.|
              TYPE 'S' DISPLAY LIKE 'E'.
    ELSE.
      MESSAGE |{ lv_name } ({ lt_found[ 1 ]-release_state }): SAP names no successor object for it.|
              TYPE 'S' DISPLAY LIKE 'E'.
    ENDIF.
  ENDMETHOD.


  METHOD show_successors.
    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = DATA(lo_alv)
                                CHANGING  t_table      = mt_successors ).
        lo_alv->get_functions( )->set_all( ).
        lo_alv->get_display_settings( )->set_list_header(
          CONV #( |Successors of { condense( p_oname ) }, read from this system| ) ).

        DATA(lo_columns) = lo_alv->get_columns( ).
        lo_columns->set_optimize( ).
        set_heading( io_columns = lo_columns iv_column = 'OBJECT_TYPE'    iv_text = 'Type' ).
        set_heading( io_columns = lo_columns iv_column = 'OBJECT_NAME'    iv_text = 'Object' ).
        set_heading( io_columns = lo_columns iv_column = 'OBJECT_STATE'   iv_text = 'State' ).
        set_heading( io_columns = lo_columns iv_column = 'SUCCESSOR_TYPE' iv_text = 'Succ. type' ).
        set_heading( io_columns = lo_columns iv_column = 'SUCCESSOR_NAME' iv_text = 'Successor' ).
        set_heading( io_columns = lo_columns iv_column = 'ABAP_CLOUD'     iv_text = 'ABAP Cloud' ).
        lo_alv->display( ).
      CATCH cx_salv_error INTO DATA(lx_error).
        MESSAGE lx_error TYPE 'S' DISPLAY LIKE 'E'.
    ENDTRY.
  ENDMETHOD.


  METHOD extract_pairs.
    DATA(lv_total) = lines( it_pairs ).

    LOOP AT it_pairs INTO DATA(ls_pair).
      DATA(lv_done) = sy-tabix.
      cl_progress_indicator=>progress_indicate(
        i_text               = |{ lv_done }/{ lv_total } { ls_pair-cds_name }|
        i_processed          = lv_done
        i_total              = lv_total
        i_output_immediately = abap_true ).
      INSERT LINES OF mo_extractor->extract( VALUE #( ( ls_pair ) ) ) INTO TABLE rt_result.
    ENDLOOP.
  ENDMETHOD.


  METHOD selected_pairs.
    DATA(lv_table) = to_upper( p_table ).

    IF p_cds IS NOT INITIAL.
      mv_source = `your input`.
      DATA(lv_cds) = to_upper( p_cds ).
      DATA(lt_states) = read_states( VALUE #( ( object_type     = 'DDLS'
                                                object_id       = lv_cds
                                                sub_object_name = lv_cds ) ) ).
      rt_pairs = VALUE #( ( table_name = lv_table
                            cds_name   = lv_cds
                            released   = xsdbool( availability( VALUE #( lt_states[ 1 ] OPTIONAL ) ) = c_released ) ) ).
      RETURN.
    ENDIF.

    DATA(lt_all) = all_pairs( ).

    rt_pairs = lt_all.
    IF lv_table IS NOT INITIAL.
      DELETE rt_pairs WHERE table_name <> lv_table.
    ENDIF.
  ENDMETHOD.


  METHOD fill_rows.
    LOOP AT it_result INTO DATA(ls_view).
      LOOP AT ls_view-mapping INTO DATA(ls_map).
        IF ls_map-table_field IS INITIAL.
          CONTINUE.
        ENDIF.
        DATA(lv_table_field) = CONV fieldname( to_upper( ls_map-table_field ) ).
        IF lv_table_field NOT IN s_field.
          CONTINUE.
        ENDIF.
        INSERT VALUE #( table_name  = ls_view-table_name
                        table_field = lv_table_field
                        cds_view    = ls_view-cds_name
                        cds_field   = ls_map-cds_field
                        match_type  = COND #( WHEN ls_map-computed = abap_true       THEN c_in_expression
                                              WHEN ls_map-table_field IS NOT INITIAL THEN c_same_column )
                        how_to_use  = COND #( WHEN ls_map-computed = abap_true THEN 'Show' )
                        release     = COND #( WHEN ls_view-released = abap_false THEN 'Not released' )
                        expression  = ls_map-expression
                        defined_in  = ls_map-defined_in )
               INTO TABLE mt_rows.
      ENDLOOP.
    ENDLOOP.

    IF s_field[] IS NOT INITIAL.
      add_coverage( requested_fields( ) ).
      RETURN.
    ENDIF.

    SORT mt_rows BY table_name table_field cds_view cds_field.
  ENDMETHOD.


  METHOD requested_fields.
    SELECT fieldname
      FROM dd03l
      WHERE tabname = @p_table
        AND as4local = 'A'
        AND fieldname IN @s_field
        AND fieldname NOT LIKE '.%'
        AND fieldname <> 'MANDT'
      INTO TABLE @rt_fields.

    LOOP AT s_field INTO DATA(ls_field) WHERE sign = 'I' AND option = 'EQ'.
      INSERT ls_field-low INTO TABLE rt_fields.
    ENDLOOP.

    SORT rt_fields BY table_line.
    DELETE ADJACENT DUPLICATES FROM rt_fields COMPARING table_line.
  ENDMETHOD.


  METHOD add_coverage.
    DATA(lt_view_fields) = mt_rows.
    DELETE lt_view_fields WHERE match_type <> c_same_column.
    SORT lt_view_fields BY cds_view table_field.
    DELETE ADJACENT DUPLICATES FROM lt_view_fields COMPARING cds_view table_field.

    DATA(lv_total) = lines( it_fields ).
    LOOP AT mt_rows ASSIGNING FIELD-SYMBOL(<ls_row>).
      <ls_row>-covered = REDUCE i( INIT lv_count = 0
                                   FOR ls_view_field IN lt_view_fields
                                   WHERE ( cds_view = <ls_row>-cds_view )
                                   NEXT lv_count = lv_count + 1 ).
    ENDLOOP.

    LOOP AT it_fields INTO DATA(lv_field).
      IF NOT line_exists( mt_rows[ table_field = lv_field ] ).
        INSERT VALUE #( table_name = p_table table_field = lv_field ) INTO TABLE mt_rows.
      ENDIF.
    ENDLOOP.

    SORT mt_rows BY covered DESCENDING cds_view table_field cds_field.

    DATA(ls_best) = VALUE #( mt_rows[ 1 ] OPTIONAL ).
    mv_note = COND #( WHEN ls_best-covered = 0
                        THEN `No listed view reads these fields directly`
                      WHEN ls_best-covered = lv_total
                        THEN |{ ls_best-cds_view } covers all { lv_total } fields directly|
                      ELSE `No single view reads all fields directly` ).
  ENDMETHOD.


  METHOD show_rows.
    IF mt_rows IS INITIAL.
      MESSAGE 'No field could be traced to a table column.' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    DATA(lt_errors) = mo_extractor->get_errors( ).
    IF lt_errors IS NOT INITIAL.
      MESSAGE |{ lines( lt_errors ) } views skipped, first: { lt_errors[ 1 ] }| TYPE 'S'.
    ENDIF.

    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = DATA(lo_alv)
                                CHANGING  t_table      = mt_rows ).
        lo_alv->get_functions( )->set_all( ).
        lo_alv->get_display_settings( )->set_list_header(
          CONV #( COND string( WHEN mv_note IS INITIAL THEN |Pairs from { mv_source }|
                               ELSE |{ mv_note }. Pairs from { mv_source }| ) ) ).

        DATA(lo_columns) = lo_alv->get_columns( ).
        lo_columns->set_optimize( ).
        set_heading( io_columns = lo_columns iv_column = 'TABLE_NAME'  iv_text = 'Table' ).
        set_heading( io_columns = lo_columns iv_column = 'TABLE_FIELD' iv_text = 'Table fld' ).
        set_heading( io_columns = lo_columns iv_column = 'CDS_VIEW'    iv_text = 'CDS view' ).
        set_heading( io_columns = lo_columns iv_column = 'CDS_FIELD'   iv_text = 'CDS field' ).
        set_heading( io_columns = lo_columns iv_column = 'MATCH_TYPE'  iv_text = 'Match' ).
        set_heading( io_columns = lo_columns iv_column = 'HOW_TO_USE'  iv_text = 'How to use' ).
        set_heading( io_columns = lo_columns iv_column = 'RELEASE'     iv_text = 'Release' ).
        lo_columns->get_column( 'RELEASE' )->set_visible(
          xsdbool( line_exists( mt_rows[ release = 'Not released' ] ) ) ).
        lo_columns->get_column( 'COVERED' )->set_technical( ).
        lo_columns->get_column( 'EXPRESSION' )->set_technical( ).
        lo_columns->get_column( 'DEFINED_IN' )->set_technical( ).
        CAST cl_salv_column_table( lo_columns->get_column( 'HOW_TO_USE' )
          )->set_cell_type( if_salv_c_cell_type=>hotspot ).
        CAST cl_salv_column_table( lo_columns->get_column( 'TABLE_NAME' )
          )->set_cell_type( if_salv_c_cell_type=>hotspot ).
        CAST cl_salv_column_table( lo_columns->get_column( 'CDS_VIEW' )
          )->set_cell_type( if_salv_c_cell_type=>hotspot ).

        DATA(lo_events) = lo_alv->get_event( ).
        SET HANDLER on_link_click FOR lo_events.

        lo_alv->display( ).
      CATCH cx_salv_error INTO DATA(lx_error).
        MESSAGE lx_error TYPE 'S' DISPLAY LIKE 'E'.
    ENDTRY.
  ENDMETHOD.


  METHOD on_link_click.
    DATA(ls_row) = VALUE ts_row( mt_rows[ row ] OPTIONAL ).

    CASE column.
      WHEN 'TABLE_NAME'.
        read_table_keys( ls_row-table_name ).
        show_keys( |{ ls_row-table_name }| ).
      WHEN 'CDS_VIEW'.
        IF ls_row-cds_view IS INITIAL.
          RETURN.
        ENDIF.
        read_view_keys( ls_row-cds_view ).
        show_keys( |{ ls_row-cds_view }| ).
      WHEN 'HOW_TO_USE'.
        IF ls_row-how_to_use IS NOT INITIAL.
          show_definition( ls_row ).
        ENDIF.
    ENDCASE.
  ENDMETHOD.


  METHOD show_definition.
    DATA(lv_text) = condense( is_row-expression ).
    IF lv_text IS INITIAL.
      MESSAGE 'The definition could not be read. Open the view in ADT.' TYPE 'S'.
      RETURN.
    ENDIF.

    REPLACE ALL OCCURRENCES OF PCRE `(?i)\s+(?=(?:when|else|end)\b)` IN lv_text WITH cl_abap_char_utilities=>newline.
    SPLIT lv_text AT cl_abap_char_utilities=>newline INTO TABLE DATA(lt_lines).
    DATA(lv_last) = lines( lt_lines ).
    lt_lines[ lv_last ] = |{ lt_lines[ lv_last ] } as { is_row-cds_field }|.

    DATA(lv_rows) = ``.
    LOOP AT lt_lines INTO DATA(lv_line).
      DATA(lv_number) = sy-tabix.
      DATA(lv_indent) = COND string( WHEN lv_line CP 'when *' OR lv_line CP 'else *' THEN `  ` ).
      lv_rows = |{ lv_rows }<tr><td class="n">{ lv_number }</td><td class="c">{ lv_indent }{ highlight( lv_line ) }</td></tr>|.
    ENDLOOP.

    DATA(lv_title) = |{ is_row-cds_field } in { is_row-defined_in } [{ sy-sysid }, { sy-mandt }]|.
    DATA(lv_style) = `<style>`
      && `body{margin:0;font-family:Consolas,'Courier New',monospace;font-size:13px;background:#fff}`
      && `h1{margin:0;padding:6px 8px;font:bold 15px Arial,sans-serif;border-bottom:3px solid #999}`
      && `table{border-collapse:collapse;margin:4px 0;width:100%}`
      && `.n{width:1%;padding:1px 8px;text-align:right;vertical-align:top;color:#888;background:#f0f0f0;border-right:1px solid #ccc}`
      && `.c{padding:1px 8px;white-space:pre-wrap;word-wrap:break-word;word-break:break-word}`
      && `b{color:#7f0055}i{color:#2a00ff;font-style:normal}`
      && `</style>`.

    cl_abap_browser=>show_html(
      title       = CONV #( lv_title )
      html_string = |<html><head><meta charset="utf-8">{ lv_style }</head><body>|
                 && |<h1>{ escape( val = lv_title format = cl_abap_format=>e_html_text ) }</h1>|
                 && |<table>{ lv_rows }</table></body></html>|
      check_html  = abap_false ).
  ENDMETHOD.


  METHOD highlight.
    rv_html = escape( val = iv_line format = cl_abap_format=>e_html_text ).
    REPLACE ALL OCCURRENCES OF PCRE `(?i)\b(?:case|when|then|else|end|cast|as|preserving|type|and|or|not|is|null)\b`
            IN rv_html WITH `<b>$0</b>`.
    REPLACE ALL OCCURRENCES OF PCRE `'[^']*'` IN rv_html WITH `<i>$0</i>`.
  ENDMETHOD.


  METHOD read_table_keys.
    SELECT CAST( field~position AS INT4 ) AS position,
           field~fieldname AS field_name,
           field~rollname  AS data_element,
           text~ddtext     AS description,
           field~datatype  AS data_type,
           field~leng      AS length
      FROM dd03l AS field
      LEFT OUTER JOIN dd04t AS text
        ON  text~rollname   = field~rollname
        AND text~ddlanguage = @sy-langu
        AND text~as4local   = 'A'
        AND text~as4vers    = '0000'
      WHERE field~tabname  = @iv_table
        AND field~as4local = 'A'
        AND field~keyflag  = 'X'
        AND field~datatype <> 'CLNT'
        AND field~fieldname NOT LIKE '.%'
      INTO CORRESPONDING FIELDS OF TABLE @mt_keys.
    SORT mt_keys BY position.
  ENDMETHOD.


  METHOD read_view_keys.
    SELECT field~position,
           field~fieldname_raw AS field_name,
           field~rollname      AS data_element,
           text~ddtext         AS description,
           field~datatype      AS data_type,
           field~leng          AS length
      FROM dd03nd AS field
      LEFT OUTER JOIN dd04t AS text
        ON  text~rollname   = field~rollname
        AND text~ddlanguage = @sy-langu
        AND text~as4local   = 'A'
        AND text~as4vers    = '0000'
      WHERE field~strucobjn = @iv_view
        AND field~as4local  = 'A'
        AND field~keyflag   = 'X'
        AND field~datatype <> 'CLNT'
      INTO CORRESPONDING FIELDS OF TABLE @mt_keys.
    SORT mt_keys BY position.
  ENDMETHOD.


  METHOD show_keys.
    IF mt_keys IS INITIAL.
      MESSAGE |No key fields found for { iv_name }| TYPE 'S'.
      RETURN.
    ENDIF.

    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = DATA(lo_popup)
                                CHANGING  t_table      = mt_keys ).
        lo_popup->get_display_settings( )->set_list_header( CONV #( |Key fields of { iv_name }| ) ).

        DATA(lo_columns) = lo_popup->get_columns( ).
        lo_columns->set_optimize( ).
        lo_columns->get_column( 'POSITION' )->set_technical( ).
        set_heading( io_columns = lo_columns iv_column = 'FIELD_NAME'   iv_text = 'Key field' ).
        set_heading( io_columns = lo_columns iv_column = 'DATA_ELEMENT' iv_text = 'Data elem' ).
        set_heading( io_columns = lo_columns iv_column = 'DESCRIPTION'  iv_text = 'Descript.' ).
        set_heading( io_columns = lo_columns iv_column = 'DATA_TYPE'    iv_text = 'Type' ).
        set_heading( io_columns = lo_columns iv_column = 'LENGTH'       iv_text = 'Length' ).

        lo_popup->set_screen_popup( start_column = 10 end_column  = 110
                                    start_line   = 5  end_line    = 20 ).
        lo_popup->display( ).
      CATCH cx_salv_error INTO DATA(lx_error).
        MESSAGE lx_error TYPE 'S' DISPLAY LIKE 'E'.
    ENDTRY.
  ENDMETHOD.


  METHOD set_heading.
    DATA(lo_column) = io_columns->get_column( iv_column ).
    lo_column->set_short_text( iv_text ).
    lo_column->set_medium_text( CONV #( iv_text ) ).
    lo_column->set_long_text( CONV #( iv_text ) ).
  ENDMETHOD.


  METHOD download.
    DATA(lv_content) = cl_abap_codepage=>convert_to( iv_json ).
    DATA(lt_binary) = cl_bcs_convert=>xstring_to_solix( lv_content ).

    cl_gui_frontend_services=>gui_download(
      EXPORTING bin_filesize = xstrlen( lv_content )
                filename     = iv_file
                filetype     = 'BIN'
      CHANGING  data_tab     = lt_binary
      EXCEPTIONS OTHERS      = 1 ).
    IF sy-subrc <> 0.
      MESSAGE |Download failed: { iv_file }| TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    MESSAGE |{ iv_written } written to { iv_file }| TYPE 'S'.
  ENDMETHOD.


  METHOD choose_file.
    DATA lv_filename TYPE string.
    DATA lv_path     TYPE string.
    DATA lv_fullpath TYPE string.

    cl_gui_frontend_services=>file_save_dialog(
      EXPORTING default_file_name = iv_default
                default_extension = `json`
      CHANGING  filename          = lv_filename
                path              = lv_path
                fullpath          = lv_fullpath
      EXCEPTIONS OTHERS           = 1 ).
    IF sy-subrc = 0.
      rv_file = lv_fullpath.
    ENDIF.
  ENDMETHOD.
ENDCLASS.


AT SELECTION-SCREEN OUTPUT.
  LOOP AT SCREEN.
    IF ( screen-group1 = 'TAB' AND ( p_obj = abap_true OR p_json = abap_true ) )
    OR ( screen-group1 = 'OBJ' AND ( p_tab = abap_true OR p_json = abap_true ) )
    OR ( screen-group1 = 'WHT' AND p_json = abap_true ).
      screen-active = '0'.
      MODIFY SCREEN.
    ENDIF.
  ENDLOOP.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_otype.
  NEW lcl_report( )->object_type_help( ).

START-OF-SELECTION.
  NEW lcl_report( )->run( ).
