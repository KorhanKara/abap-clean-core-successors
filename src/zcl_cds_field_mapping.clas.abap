CLASS zcl_cds_field_mapping DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES: BEGIN OF ts_pair,
             table_name TYPE string,
             cds_name   TYPE string,
             released   TYPE abap_bool,
           END OF ts_pair,
           tt_pair TYPE STANDARD TABLE OF ts_pair WITH EMPTY KEY.

    TYPES: BEGIN OF ts_field_map,
             cds_field   TYPE string,
             table_field TYPE string,
             computed    TYPE abap_bool,
             expression  TYPE string,
             defined_in  TYPE string,
           END OF ts_field_map,
           tt_field_map TYPE STANDARD TABLE OF ts_field_map WITH EMPTY KEY.

    TYPES: BEGIN OF ts_view_map,
             cds_name   TYPE string,
             table_name TYPE string,
             released   TYPE abap_bool,
             mapping    TYPE tt_field_map,
           END OF ts_view_map,
           tt_view_map TYPE STANDARD TABLE OF ts_view_map WITH EMPTY KEY.

    METHODS extract
      IMPORTING it_pairs         TYPE tt_pair
      RETURNING VALUE(rt_result) TYPE tt_view_map.

    METHODS to_json
      IMPORTING it_result      TYPE tt_view_map
      RETURNING VALUE(rv_json) TYPE string.

    METHODS get_errors
      RETURNING VALUE(rt_errors) TYPE string_table.

  PRIVATE SECTION.
    CONSTANTS c_max_depth TYPE i VALUE 10.

    TYPES: BEGIN OF ts_source,
             alias  TYPE string,
             entity TYPE string,
           END OF ts_source,
           tt_source TYPE SORTED TABLE OF ts_source WITH UNIQUE KEY alias.

    TYPES: BEGIN OF ts_origin,
             entity TYPE string,
             field  TYPE string,
           END OF ts_origin,
           tt_origin TYPE STANDARD TABLE OF ts_origin WITH EMPTY KEY.

    TYPES: BEGIN OF ts_column,
             field         TYPE string,
             name          TYPE string,
             source_entity TYPE string,
             source_field  TYPE string,
             origins       TYPE tt_origin,
             computed      TYPE tt_origin,
             expression    TYPE string,
           END OF ts_column,
           tt_column TYPE SORTED TABLE OF ts_column WITH UNIQUE KEY field.

    TYPES: BEGIN OF ts_view,
             name    TYPE string,
             found   TYPE abap_bool,
             columns TYPE tt_column,
           END OF ts_view,
           tt_view TYPE HASHED TABLE OF ts_view WITH UNIQUE KEY name.

    TYPES: BEGIN OF ts_name,
             upper    TYPE string,
             original TYPE string,
           END OF ts_name,
           tt_name TYPE HASHED TABLE OF ts_name WITH UNIQUE KEY upper.

    TYPES: BEGIN OF ts_candidate,
             field     TYPE fieldname,
             tabname   TYPE tabname,
             fieldname TYPE fieldname,
           END OF ts_candidate,
           tt_candidate TYPE STANDARD TABLE OF ts_candidate WITH EMPTY KEY.

    TYPES: BEGIN OF ts_read,
             field      TYPE string,
             expression TYPE string,
             defined_in TYPE string,
           END OF ts_read,
           tt_read TYPE STANDARD TABLE OF ts_read WITH EMPTY KEY.

    TYPES: BEGIN OF ts_table,
             name    TYPE tabname,
             columns TYPE SORTED TABLE OF fieldname WITH NON-UNIQUE KEY table_line,
           END OF ts_table,
           tt_table TYPE HASHED TABLE OF ts_table WITH UNIQUE KEY name.

    DATA mt_views  TYPE tt_view.
    DATA mt_tables TYPE tt_table.
    DATA mt_errors TYPE string_table.

    METHODS read_view
      IMPORTING iv_name        TYPE string
      RETURNING VALUE(rs_view) TYPE ts_view.

    METHODS read_view_dictionary
      IMPORTING iv_name        TYPE string
      RETURNING VALUE(rs_view) TYPE ts_view.

    METHODS read_view_xco
      IMPORTING iv_name        TYPE string
      RETURNING VALUE(rs_view) TYPE ts_view.

    METHODS field_names
      IMPORTING iv_name         TYPE string
      RETURNING VALUE(rt_names) TYPE tt_name.

    METHODS trace_field
      IMPORTING iv_view               TYPE string
                iv_field              TYPE string
                iv_table              TYPE string
                iv_depth              TYPE i DEFAULT 0
      RETURNING VALUE(rv_table_field) TYPE string.

    METHODS trace_computed
      IMPORTING iv_view          TYPE string
                iv_field         TYPE string
                iv_table         TYPE string
                iv_depth         TYPE i DEFAULT 0
      RETURNING VALUE(rt_fields) TYPE tt_read.

    METHODS table_has_column
      IMPORTING iv_table       TYPE string
                iv_field       TYPE string
      RETURNING VALUE(rv_found) TYPE abap_bool.

    METHODS parse_references
      IMPORTING iv_expression  TYPE string
                it_sources     TYPE tt_source
                iv_main        TYPE string
      RETURNING VALUE(rt_refs) TYPE tt_origin.

    METHODS parse_data_source
      IMPORTING io_source        TYPE REF TO if_xco_ddl_expr_data_source
      RETURNING VALUE(rs_source) TYPE ts_source.

    METHODS sources_from_ddl
      IMPORTING iv_name           TYPE string
      EXPORTING ev_main           TYPE string
      RETURNING VALUE(rt_sources) TYPE tt_source.

    METHODS display_name
      IMPORTING iv_name        TYPE string
                iv_alias       TYPE string
                iv_expression  TYPE string
      RETURNING VALUE(rv_name) TYPE string.

    METHODS parse_column
      IMPORTING iv_expression    TYPE string
                it_sources       TYPE tt_source
                iv_main          TYPE string
      RETURNING VALUE(rs_column) TYPE ts_column.

    METHODS expression_text
      IMPORTING io_expression  TYPE REF TO if_xco_ddl_expression
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.


CLASS zcl_cds_field_mapping IMPLEMENTATION.
  METHOD extract.
    LOOP AT it_pairs INTO DATA(ls_pair).
      DATA(lv_cds) = to_upper( ls_pair-cds_name ).
      DATA(lv_table) = to_upper( ls_pair-table_name ).
      DATA(ls_view) = read_view( lv_cds ).
      IF ls_view-found = abap_false.
        INSERT |NOT_FOUND: { lv_cds }| INTO TABLE mt_errors.
        CONTINUE.
      ENDIF.

      INSERT VALUE #( cds_name   = lv_cds
                      table_name = lv_table
                      released   = ls_pair-released )
             INTO TABLE rt_result REFERENCE INTO DATA(lr_result).

      LOOP AT ls_view-columns INTO DATA(ls_column).
        DATA(lv_direct) = trace_field( iv_view  = lv_cds
                                       iv_field = ls_column-field
                                       iv_table = lv_table ).
        DATA(lt_read) = COND tt_read( WHEN lv_direct IS INITIAL
                                      THEN trace_computed( iv_view  = lv_cds
                                                           iv_field = ls_column-field
                                                           iv_table = lv_table ) ).
        IF lt_read IS INITIAL.
          INSERT VALUE #( cds_field = ls_column-name table_field = lv_direct ) INTO TABLE lr_result->mapping.
          CONTINUE.
        ENDIF.

        LOOP AT lt_read INTO DATA(ls_read).
          INSERT VALUE #( cds_field   = ls_column-name
                          table_field = ls_read-field
                          computed    = abap_true
                          expression  = ls_read-expression
                          defined_in  = ls_read-defined_in )
                 INTO TABLE lr_result->mapping.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD to_json.
    rv_json = /ui2/cl_json=>serialize( data        = it_result
                                       pretty_name = /ui2/cl_json=>pretty_mode-camel_case ).
  ENDMETHOD.


  METHOD get_errors.
    rt_errors = mt_errors.
  ENDMETHOD.


  METHOD read_view.
    READ TABLE mt_views INTO rs_view WITH TABLE KEY name = iv_name.
    IF sy-subrc = 0.
      RETURN.
    ENDIF.

    rs_view = read_view_dictionary( iv_name ).
    IF rs_view-found = abap_false.
      rs_view = read_view_xco( iv_name ).
    ENDIF.
    rs_view-name = iv_name.
    INSERT rs_view INTO TABLE mt_views.
  ENDMETHOD.


  METHOD read_view_dictionary.
    DATA(lv_ddl_name) = iv_name.
    SELECT SINGLE FROM ddldependency
      FIELDS objectname
      WHERE ddlname = @iv_name
        AND objecttype = 'VIEW'
        AND state = 'A'
      INTO @DATA(lv_sql_view).
    IF sy-subrc <> 0.
      lv_sql_view = iv_name.
      SELECT SINGLE FROM ddldependency
        FIELDS ddlname
        WHERE objectname = @iv_name
          AND objecttype = 'VIEW'
          AND state = 'A'
        INTO @DATA(lv_owner_ddl).
      lv_ddl_name = COND #( WHEN sy-subrc = 0 THEN CONV string( lv_owner_ddl ) ).
    ENDIF.

    SELECT FROM dd27s
      FIELDS objpos, viewfield, tabname, fieldname
      WHERE viewname = @lv_sql_view
        AND as4local = 'A'
      ORDER BY objpos
      INTO TABLE @DATA(lt_fields).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    rs_view-found = abap_true.
    DATA(lt_names) = field_names( iv_name ).
    DATA(lt_computed) = VALUE string_table( ).

    LOOP AT lt_fields INTO DATA(ls_field).
      IF ls_field-viewfield CP '.*' OR ls_field-viewfield = 'MANDT'.
        CONTINUE.
      ENDIF.

      DATA(lv_field) = CONV string( ls_field-viewfield ).
      READ TABLE rs_view-columns ASSIGNING FIELD-SYMBOL(<ls_field_column>) WITH TABLE KEY field = lv_field.
      IF sy-subrc <> 0.
        INSERT VALUE #( field = lv_field
                        name  = VALUE #( lt_names[ upper = lv_field ]-original DEFAULT lv_field ) )
               INTO TABLE rs_view-columns ASSIGNING <ls_field_column>.
      ENDIF.

      IF ls_field-tabname NP 'DDDDL*TYPES'.
        INSERT VALUE #( entity = ls_field-tabname field = ls_field-fieldname ) INTO TABLE <ls_field_column>-origins.
      ELSE.
        INSERT lv_field INTO TABLE lt_computed.
      ENDIF.
    ENDLOOP.

    IF lt_computed IS INITIAL OR lv_ddl_name IS INITIAL.
      RETURN.
    ENDIF.
    SORT lt_computed.
    DELETE ADJACENT DUPLICATES FROM lt_computed.

    DATA(ls_parsed) = read_view_xco( lv_ddl_name ).
    DATA(lt_candidates) = VALUE tt_candidate( ).
    LOOP AT lt_computed INTO DATA(lv_computed).
      READ TABLE ls_parsed-columns INTO DATA(ls_parsed_column) WITH TABLE KEY field = lv_computed.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      IF ls_parsed_column-source_entity IS NOT INITIAL.
        INSERT VALUE #( field     = lv_computed
                        tabname   = ls_parsed_column-source_entity
                        fieldname = ls_parsed_column-source_field ) INTO TABLE lt_candidates.
      ELSE.
        READ TABLE rs_view-columns ASSIGNING FIELD-SYMBOL(<ls_computed>) WITH TABLE KEY field = lv_computed.
        <ls_computed>-computed = ls_parsed_column-computed.
        <ls_computed>-expression = ls_parsed_column-expression.
      ENDIF.
    ENDLOOP.
    IF lt_candidates IS INITIAL.
      RETURN.
    ENDIF.

    SELECT FROM @lt_candidates AS cand
      INNER JOIN dd03l AS col
        ON  col~tabname   = cand~tabname
        AND col~fieldname = cand~fieldname
      FIELDS cand~field, cand~tabname, cand~fieldname
      WHERE col~as4local = 'A'
      INTO TABLE @DATA(lt_confirmed).

    LOOP AT lt_candidates INTO DATA(ls_candidate).
      IF line_exists( lt_confirmed[ field = ls_candidate-field ] ).
        CONTINUE.
      ENDIF.
      DATA(ls_source_view) = read_view( CONV #( ls_candidate-tabname ) ).
      IF line_exists( ls_source_view-columns[ field = CONV string( ls_candidate-fieldname ) ] ).
        INSERT ls_candidate INTO TABLE lt_confirmed.
      ENDIF.
    ENDLOOP.

    LOOP AT lt_confirmed INTO DATA(ls_confirmed).
      READ TABLE rs_view-columns ASSIGNING FIELD-SYMBOL(<ls_column>) WITH TABLE KEY field = CONV string( ls_confirmed-field ).
      IF sy-subrc = 0.
        INSERT VALUE #( entity = ls_confirmed-tabname field = ls_confirmed-fieldname ) INTO TABLE <ls_column>-origins.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD field_names.
    SELECT SINGLE FROM ddddlsrc
      FIELDS source
      WHERE ddlname = @iv_name
        AND as4local = 'A'
      INTO @DATA(lv_source).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    REPLACE ALL OCCURRENCES OF PCRE `//[^\n]*` IN lv_source WITH ``.
    REPLACE ALL OCCURRENCES OF PCRE `(?s)/\*.*?\*/` IN lv_source WITH ``.

    FIND ALL OCCURRENCES OF PCRE `(?i)\bas\s+([A-Za-z_][A-Za-z0-9_]*)\b(?!\s*(?:\)|preserving\b))` IN lv_source RESULTS DATA(lt_aliases).
    FIND ALL OCCURRENCES OF PCRE `([A-Za-z_][A-Za-z0-9_]*)\s*[,}]` IN lv_source RESULTS DATA(lt_plain).
    INSERT LINES OF lt_plain INTO TABLE lt_aliases.

    LOOP AT lt_aliases INTO DATA(ls_match).
      DATA(lv_token) = substring( val = lv_source
                                  off = ls_match-submatches[ 1 ]-offset
                                  len = ls_match-submatches[ 1 ]-length ).
      INSERT VALUE #( upper = to_upper( lv_token ) original = lv_token ) INTO TABLE rt_names.
    ENDLOOP.
  ENDMETHOD.


  METHOD read_view_xco.
    DATA lv_main  TYPE string.
    DATA lv_alias TYPE string.
    DATA lt_joins TYPE sxco_t_ddl_expr_data_sources.
    DATA lt_fields TYPE sxco_t_cds_fields.

    TRY.
        DATA(lo_view) = xco_cds=>view( CONV #( iv_name ) ).
        DATA(lo_entity) = xco_cds=>view_entity( CONV #( iv_name ) ).
        IF lo_view->exists( ).
          lt_fields = lo_view->fields->all->get( ).
          rs_view-found = abap_true.
        ELSEIF lo_entity->exists( ).
          lt_fields = lo_entity->fields->all->get( ).
          rs_view-found = abap_true.
        ENDIF.
      CATCH cx_root INTO DATA(lx_error).
        INSERT |READ_ERROR: { iv_name }: { lx_error->get_text( ) }| INTO TABLE mt_errors.
        CLEAR rs_view-found.
    ENDTRY.

    IF rs_view-found = abap_false.
      RETURN.
    ENDIF.

    TRY.
        IF lo_view->exists( ).
          DATA(ls_view_source) = lo_view->content( )->get_data_source( ).
          lv_main = ls_view_source-entity.
          lv_alias = ls_view_source-alias.
          INSERT LINES OF ls_view_source-inner_joins INTO TABLE lt_joins.
          INSERT LINES OF ls_view_source-left_outer_joins INTO TABLE lt_joins.
          INSERT LINES OF ls_view_source-right_outer_joins INTO TABLE lt_joins.
        ELSE.
          DATA(ls_entity_source) = lo_entity->content( )->get_data_source( ).
          lv_main = ls_entity_source-view_entity.
          lv_alias = ls_entity_source-alias.
          INSERT LINES OF ls_entity_source-inner_joins INTO TABLE lt_joins.
          INSERT LINES OF ls_entity_source-left_outer_joins INTO TABLE lt_joins.
          INSERT LINES OF ls_entity_source-right_outer_joins INTO TABLE lt_joins.
        ENDIF.
      CATCH cx_root.
        CLEAR: lv_main, lv_alias, lt_joins.
    ENDTRY.

    DATA(lt_sources) = VALUE tt_source( ).
    IF lv_main IS INITIAL.
      lt_sources = sources_from_ddl( EXPORTING iv_name = iv_name
                                     IMPORTING ev_main = lv_main ).
      IF lv_main IS INITIAL.
        INSERT |SOURCE_UNKNOWN: { iv_name }| INTO TABLE mt_errors.
      ENDIF.
    ELSE.
      lv_main = to_upper( lv_main ).
      INSERT VALUE #( alias = lv_main entity = lv_main ) INTO TABLE lt_sources.
      IF lv_alias IS NOT INITIAL.
        INSERT VALUE #( alias = to_upper( lv_alias ) entity = lv_main ) INTO TABLE lt_sources.
      ENDIF.

      LOOP AT lt_joins INTO DATA(lo_join).
        DATA(ls_join_source) = parse_data_source( lo_join ).
        IF ls_join_source-entity IS INITIAL.
          CONTINUE.
        ENDIF.
        INSERT VALUE #( alias = ls_join_source-entity entity = ls_join_source-entity ) INTO TABLE lt_sources.
        IF ls_join_source-alias IS NOT INITIAL.
          INSERT ls_join_source INTO TABLE lt_sources.
        ENDIF.
      ENDLOOP.
    ENDIF.

    LOOP AT lt_fields INTO DATA(lo_field).
      IF lo_field->name CP `_*`.
        CONTINUE.
      ENDIF.

      DATA(lv_expression) = VALUE string( ).
      DATA(lv_field_alias) = VALUE string( ).
      TRY.
          DATA(lo_field_content) = lo_field->content( ).
          lv_expression = expression_text( lo_field_content->get_expression( ) ).
          lv_field_alias = lo_field_content->get_alias( ).
        CATCH cx_root.
          CLEAR: lv_expression, lv_field_alias.
      ENDTRY.

      DATA(ls_column) = parse_column( iv_expression = lv_expression
                                      it_sources    = lt_sources
                                      iv_main       = lv_main ).
      IF ls_column-source_entity IS INITIAL.
        ls_column-computed = parse_references( iv_expression = lv_expression
                                               it_sources    = lt_sources
                                               iv_main       = lv_main ).
        ls_column-expression = lv_expression.
      ENDIF.
      ls_column-field = to_upper( lo_field->name ).
      ls_column-name = display_name( iv_name       = ls_column-field
                                     iv_alias      = lv_field_alias
                                     iv_expression = lv_expression ).
      INSERT ls_column INTO TABLE rs_view-columns.
    ENDLOOP.
  ENDMETHOD.


  METHOD display_name.
    rv_name = iv_name.
    IF iv_alias IS NOT INITIAL AND to_upper( iv_alias ) = iv_name.
      rv_name = iv_alias.
      RETURN.
    ENDIF.

    FIND FIRST OCCURRENCE OF PCRE `([A-Za-z0-9_/$]+)\s*$` IN condense( iv_expression ) SUBMATCHES DATA(lv_last_token).
    IF sy-subrc = 0 AND to_upper( lv_last_token ) = iv_name.
      rv_name = lv_last_token.
    ENDIF.
  ENDMETHOD.


  METHOD sources_from_ddl.
    SELECT SINGLE FROM ddddlsrc
      FIELDS source
      WHERE ddlname = @iv_name
        AND as4local = 'A'
      INTO @DATA(lv_source).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    lv_source = to_upper( lv_source ).
    REPLACE ALL OCCURRENCES OF PCRE `//[^\n]*` IN lv_source WITH ``.
    REPLACE ALL OCCURRENCES OF PCRE `(?s)/\*.*?\*/` IN lv_source WITH ``.

    FIND ALL OCCURRENCES OF PCRE `\b(FROM|JOIN)\s+([A-Z0-9_/]+)(?:\s*\([^)]*\))?(?:\s+AS\s+([A-Z0-9_/]+))?`
         IN lv_source RESULTS DATA(lt_matches).

    LOOP AT lt_matches INTO DATA(ls_match).
      DATA(lv_keyword) = substring( val = lv_source
                                    off = ls_match-submatches[ 1 ]-offset
                                    len = ls_match-submatches[ 1 ]-length ).
      DATA(lv_entity) = substring( val = lv_source
                                   off = ls_match-submatches[ 2 ]-offset
                                   len = ls_match-submatches[ 2 ]-length ).
      DATA(ls_alias_match) = ls_match-submatches[ 3 ].
      DATA(lv_alias) = COND string( WHEN ls_alias_match-offset >= 0 AND ls_alias_match-length > 0
                                    THEN substring( val = lv_source
                                                    off = ls_alias_match-offset
                                                    len = ls_alias_match-length ) ).

      IF lv_keyword = `FROM` AND ev_main IS INITIAL.
        ev_main = lv_entity.
      ENDIF.
      INSERT VALUE #( alias = lv_entity entity = lv_entity ) INTO TABLE rt_sources.
      IF lv_alias IS NOT INITIAL.
        INSERT VALUE #( alias = lv_alias entity = lv_entity ) INTO TABLE rt_sources.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD trace_field.
    IF iv_depth > c_max_depth.
      RETURN.
    ENDIF.

    DATA(ls_view) = read_view( iv_view ).
    READ TABLE ls_view-columns INTO DATA(ls_column) WITH TABLE KEY field = iv_field.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA(lt_origins) = ls_column-origins.
    IF ls_column-source_entity IS NOT INITIAL.
      INSERT VALUE #( entity = ls_column-source_entity field = ls_column-source_field ) INTO TABLE lt_origins.
    ENDIF.

    rv_table_field = VALUE #( lt_origins[ entity = iv_table ]-field OPTIONAL ).
    IF rv_table_field IS NOT INITIAL.
      RETURN.
    ENDIF.

    LOOP AT lt_origins INTO DATA(ls_origin).
      IF read_view( ls_origin-entity )-found = abap_false.
        CONTINUE.
      ENDIF.
      rv_table_field = trace_field( iv_view  = ls_origin-entity
                                    iv_field = ls_origin-field
                                    iv_table = iv_table
                                    iv_depth = iv_depth + 1 ).
      IF rv_table_field IS NOT INITIAL.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD trace_computed.
    IF iv_depth > c_max_depth.
      RETURN.
    ENDIF.

    DATA(ls_view) = read_view( iv_view ).
    READ TABLE ls_view-columns INTO DATA(ls_column) WITH TABLE KEY field = iv_field.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    LOOP AT ls_column-computed INTO DATA(ls_reference).
      IF ls_reference-entity = iv_table.
        IF table_has_column( iv_table = iv_table iv_field = ls_reference-field ) = abap_true.
          INSERT VALUE #( field      = ls_reference-field
                          expression = ls_column-expression
                          defined_in = iv_view ) INTO TABLE rt_fields.
        ENDIF.
        CONTINUE.
      ENDIF.
      IF read_view( ls_reference-entity )-found = abap_false.
        CONTINUE.
      ENDIF.

      DATA(lv_direct) = trace_field( iv_view  = ls_reference-entity
                                     iv_field = ls_reference-field
                                     iv_table = iv_table
                                     iv_depth = iv_depth + 1 ).
      IF lv_direct IS NOT INITIAL.
        INSERT VALUE #( field      = lv_direct
                        expression = ls_column-expression
                        defined_in = iv_view ) INTO TABLE rt_fields.
      ELSE.
        INSERT LINES OF trace_computed( iv_view  = ls_reference-entity
                                        iv_field = ls_reference-field
                                        iv_table = iv_table
                                        iv_depth = iv_depth + 1 ) INTO TABLE rt_fields.
      ENDIF.
    ENDLOOP.

    DATA(lt_origins) = ls_column-origins.
    IF ls_column-source_entity IS NOT INITIAL.
      INSERT VALUE #( entity = ls_column-source_entity field = ls_column-source_field ) INTO TABLE lt_origins.
    ENDIF.

    LOOP AT lt_origins INTO DATA(ls_origin).
      IF read_view( ls_origin-entity )-found = abap_true.
        INSERT LINES OF trace_computed( iv_view  = ls_origin-entity
                                        iv_field = ls_origin-field
                                        iv_table = iv_table
                                        iv_depth = iv_depth + 1 ) INTO TABLE rt_fields.
      ENDIF.
    ENDLOOP.

    SORT rt_fields BY field.
    DELETE ADJACENT DUPLICATES FROM rt_fields COMPARING field.
  ENDMETHOD.


  METHOD table_has_column.
    DATA(lv_table) = CONV tabname( iv_table ).
    READ TABLE mt_tables REFERENCE INTO DATA(lr_table) WITH TABLE KEY name = lv_table.
    IF sy-subrc <> 0.
      DATA(ls_table) = VALUE ts_table( name = lv_table ).
      SELECT FROM dd03l
        FIELDS fieldname
        WHERE tabname = @lv_table
          AND as4local = 'A'
        INTO TABLE @ls_table-columns.
      INSERT ls_table INTO TABLE mt_tables REFERENCE INTO lr_table.
    ENDIF.

    rv_found = xsdbool( line_exists( lr_table->columns[ table_line = CONV fieldname( iv_field ) ] ) ).
  ENDMETHOD.


  METHOD parse_references.
    DATA(lv_text) = to_upper( iv_expression ).
    REPLACE ALL OCCURRENCES OF PCRE `'[^']*'` IN lv_text WITH ` `.
    REPLACE ALL OCCURRENCES OF PCRE `\bAS\s+[A-Z0-9_./]+(?:\s*\([^)]*\))?` IN lv_text WITH ` `.
    REPLACE ALL OCCURRENCES OF PCRE `\bPRESERVING\s+TYPE\b` IN lv_text WITH ` `.

    FIND ALL OCCURRENCES OF PCRE `(?<![A-Z0-9_/$.])([A-Z_/][A-Z0-9_/]*)(?:\.([A-Z0-9_/]+))?\b(?!\s*\()`
         IN lv_text RESULTS DATA(lt_matches).

    LOOP AT lt_matches INTO DATA(ls_match).
      DATA(ls_first) = ls_match-submatches[ 1 ].
      DATA(ls_second) = ls_match-submatches[ 2 ].
      DATA(lv_first) = substring( val = lv_text off = ls_first-offset len = ls_first-length ).

      IF ls_second-offset < 0.
        IF iv_main IS NOT INITIAL.
          INSERT VALUE #( entity = iv_main field = lv_first ) INTO TABLE rt_refs.
        ENDIF.
        CONTINUE.
      ENDIF.

      READ TABLE it_sources INTO DATA(ls_source) WITH TABLE KEY alias = lv_first.
      IF sy-subrc = 0.
        INSERT VALUE #( entity = ls_source-entity
                        field  = substring( val = lv_text off = ls_second-offset len = ls_second-length ) )
               INTO TABLE rt_refs.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD parse_data_source.
    DATA(lv_text) = to_upper( condense( expression_text( io_source ) ) ).
    SPLIT lv_text AT ` ` INTO TABLE DATA(lt_tokens).
    DELETE lt_tokens WHERE table_line IS INITIAL
                        OR table_line = `INNER` OR table_line = `LEFT` OR table_line = `RIGHT`
                        OR table_line = `OUTER` OR table_line = `JOIN` OR table_line = `CROSS`
                        OR table_line = `TO` OR table_line = `ONE` OR table_line = `MANY`
                        OR table_line = `EXACT`.

    LOOP AT lt_tokens INTO DATA(lv_token).
      DATA(lv_index) = sy-tabix.
      IF rs_source-entity IS INITIAL.
        SPLIT lv_token AT `(` INTO rs_source-entity DATA(lv_rest).
        CONTINUE.
      ENDIF.
      IF lv_token = `AS` AND line_exists( lt_tokens[ lv_index + 1 ] ).
        rs_source-alias = lt_tokens[ lv_index + 1 ].
      ENDIF.
      EXIT.
    ENDLOOP.
  ENDMETHOD.


  METHOD parse_column.
    DATA(lv_text) = to_upper( condense( iv_expression ) ).

    FIND FIRST OCCURRENCE OF PCRE `^(?:CAST\s*\(\s*)+([A-Z0-9_/$.]+)\s+AS\s` IN lv_text SUBMATCHES DATA(lv_cast_inner).
    IF sy-subrc = 0.
      lv_text = lv_cast_inner.
    ENDIF.

    FIND FIRST OCCURRENCE OF PCRE `^[A-Z0-9_/$]+(\.[A-Z0-9_/$]+)?$` IN lv_text.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    IF lv_text CS `.`.
      SPLIT lv_text AT `.` INTO DATA(lv_qualifier) DATA(lv_field).
      READ TABLE it_sources INTO DATA(ls_source) WITH TABLE KEY alias = lv_qualifier.
      IF sy-subrc <> 0.
        RETURN.
      ENDIF.
      rs_column-source_entity = ls_source-entity.
      rs_column-source_field = lv_field.
    ELSE.
      rs_column-source_entity = iv_main.
      rs_column-source_field = lv_text.
    ENDIF.
  ENDMETHOD.


  METHOD expression_text.
    IF io_expression IS NOT BOUND.
      RETURN.
    ENDIF.
    rv_text = concat_lines_of( table = io_expression->if_xco_text~get_lines( )->value
                               sep   = ` ` ).
  ENDMETHOD.

ENDCLASS.
