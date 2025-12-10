*&---------------------------------------------------------------------*
*& Report  Z_TEST_AZURE_PUSH
*& Description: Native HTTP POST to Azure Function (Works on ECC 6.0)
*& Purpose: Test SAP → Azure connectivity before full integration
*&---------------------------------------------------------------------*
REPORT Z_TEST_AZURE_PUSH.

DATA: lo_http_client TYPE REF TO if_http_client,
      lv_url         TYPE string,
      lv_payload     TYPE string,
      lv_response    TYPE string,
      lv_status_code TYPE i,
      lv_status_text TYPE string.

* 1. CONFIGURATION
* Replace with your specific Azure Function URL
lv_url = 'https://func-sap-demo.azurewebsites.net/api/ReceiveSAPStatus?code=YourFunctionKey=='.

* 2. BUILD JSON PAYLOAD
* (Manual JSON construction is safer on old NetWeaver versions than using transformations)
CONCATENATE '{"vendorId": "100050", "status": "Success", "message": "Vendor created via BAPI"}'
       INTO lv_payload.

* 3. CREATE HTTP CLIENT
CALL METHOD cl_http_client=>create_by_url
  EXPORTING
    url                = lv_url
  IMPORTING
    client             = lo_http_client
  EXCEPTIONS
    argument_not_found = 1
    plugin_not_active  = 2
    internal_error     = 3
    OTHERS             = 4.

IF sy-subrc <> 0.
  WRITE: / 'Error: Could not create HTTP client'.
  EXIT.
ENDIF.

* 4. SET REQUEST METHOD & HEADERS
lo_http_client->request->set_method( 'POST' ).
lo_http_client->request->set_content_type( 'application/json' ).
lo_http_client->request->set_cdata( data = lv_payload ).

* 5. SEND REQUEST
CALL METHOD lo_http_client->send
  EXCEPTIONS
    http_communication_failure = 1
    http_invalid_state         = 2
    http_processing_failed     = 3
    http_invalid_timeout       = 4
    OTHERS                     = 5.

IF sy-subrc <> 0.
  CALL METHOD lo_http_client->get_last_error
    IMPORTING
      message = lv_status_text.
  WRITE: / 'Error Sending:', lv_status_text.
  EXIT.
ENDIF.

* 6. RECEIVE RESPONSE
CALL METHOD lo_http_client->receive
  EXCEPTIONS
    http_communication_failure = 1
    http_invalid_state         = 2
    http_processing_failed     = 3
    OTHERS                     = 4.

IF sy-subrc <> 0.
  CALL METHOD lo_http_client->get_last_error
    IMPORTING
      message = lv_status_text.
  WRITE: / 'Error Receiving:', lv_status_text.
  EXIT.
ENDIF.

* 7. DISPLAY RESULT
lo_http_client->response->get_status( IMPORTING code = lv_status_code reason = lv_status_text ).

WRITE: / '-------------------------------------------------'.
WRITE: / 'Azure Response Code:', lv_status_code.
WRITE: / 'Azure Response Text:', lv_status_text.
WRITE: / '-------------------------------------------------'.

* Close connection to free resources
lo_http_client->close( ).
