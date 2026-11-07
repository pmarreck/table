port module Main exposing (main)

import Browser
import Dict exposing (Dict)
import Html as H exposing (Html)
import Html.Attributes as A
import Html.Events as E
import Json.Encode as J
import Process
import Task


port toEngine : J.Value -> Cmd msg


port fromEngine : (Reply -> msg) -> Sub msg


type Format
    = Csv
    | Tsv
    | Markdown
    | Ascii
    | Ansi
    | Ir


type Setting
    = Width
    | Alignment
    | Overflow
    | Decimal
    | Color
    | Borders
    | Glyphs


type Toggle
    = Header
    | Lossy
    | Plain


type alias Column =
    { width : String, alignment : String, overflow : String }


type alias Reply =
    { kind : String, token : Int, ok : Bool, source : String, rows : Int, columns : Int, display : String, error : String, bytes : Int }


type alias ConversionResult =
    { display : String, bytes : Int }


type alias Model =
    { input : String
    , source : Maybe Format
    , destination : Format
    , detected : Maybe Format
    , ready : Bool
    , inspecting : Bool
    , busy : Bool
    , token : Int
    , rows : Int
    , columns : Int
    , result : Maybe ConversionResult
    , error : String
    , copyStatus : String
    , header : Bool
    , lossy : Bool
    , plain : Bool
    , width : String
    , alignment : String
    , overflow : String
    , decimal : String
    , color : String
    , borders : String
    , glyphs : String
    , overrides : Dict Int Column
    , page : Int
    , legend : String
    }


type Msg
    = EditInput String
    | SetSource String
    | SetDestination String
    | SetSetting Setting String
    | SetToggle Toggle Bool
    | SetColumn Int Setting String
    | SetPage Int
    | Inspect Int
    | Convert
    | Received Reply
    | Copy
    | Download
    | ResetCopy Int
    | Example
    | Clear


sample : String
sample =
    "Name,Team,Score\nAlex,Design,98\nSam,Engineering,100\nYuki,Research,95\n"


main : Program () Model Msg
main =
    Browser.element
        { init = \_ -> ( initial, Cmd.none )
        , update = update
        , subscriptions = \_ -> fromEngine Received
        , view = view
        }


initial : Model
initial =
    { input = sample
    , source = Nothing
    , destination = Markdown
    , detected = Nothing
    , ready = False
    , inspecting = False
    , busy = False
    , token = 1
    , rows = 0
    , columns = 0
    , result = Nothing
    , error = ""
    , copyStatus = ""
    , header = True
    , lossy = False
    , plain = False
    , width = "80"
    , alignment = "auto"
    , overflow = "auto"
    , decimal = "."
    , color = "auto"
    , borders = "auto"
    , glyphs = "+,+,+,+,+,+,+,+,+,-,|"
    , overrides = Dict.empty
    , page = 0
    , legend = ""
    }


names : List ( Format, String, String )
names =
    [ ( Csv, "csv", "CSV" )
    , ( Tsv, "tsv", "TSV" )
    , ( Markdown, "markdown", "Markdown" )
    , ( Ascii, "ascii", "ASCII table" )
    , ( Ansi, "ansi", "ANSI table" )
    , ( Ir, "ir", "IR" )
    ]


formatName : Format -> String
formatName format =
    case format of
        Csv ->
            "csv"

        Tsv ->
            "tsv"

        Markdown ->
            "markdown"

        Ascii ->
            "ascii"

        Ansi ->
            "ansi"

        Ir ->
            "ir"


formatLabel : Format -> String
formatLabel format =
    names |> List.filter (\( f, _, _ ) -> f == format) |> List.head |> Maybe.map (\( _, _, label ) -> label) |> Maybe.withDefault ""


parseFormat : String -> Maybe Format
parseFormat name =
    names |> List.filter (\( _, value, _ ) -> value == name) |> List.head |> Maybe.map (\( f, _, _ ) -> f)


visual : Maybe Format -> Bool
visual format =
    format == Just Ascii || format == Just Ansi


effectiveSource : Model -> Maybe Format
effectiveSource model =
    case model.source of
        Nothing ->
            model.detected

        chosen ->
            chosen


changed : Model -> ( Model, Cmd Msg )
changed model =
    let
        next =
            { model | token = model.token + 1, result = Nothing, error = "", copyStatus = "", busy = False, inspecting = model.ready }
    in
    ( next
    , Cmd.batch
        [ toEngine (J.object [ ( "kind", J.string "invalidate" ), ( "token", J.int next.token ) ])
        , Process.sleep 220 |> Task.perform (\_ -> Inspect next.token)
        ]
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        EditInput value ->
            changed { model | input = value, detected = Nothing }

        SetSource value ->
            changed { model | source = parseFormat value, detected = Nothing, page = 0 }

        SetDestination value ->
            case parseFormat value of
                Just format ->
                    changed { model | destination = format }

                Nothing ->
                    ( model, Cmd.none )

        SetSetting setting value ->
            changed
                (case setting of
                    Width ->
                        { model | width = value }

                    Alignment ->
                        { model | alignment = value }

                    Overflow ->
                        { model | overflow = value }

                    Decimal ->
                        { model | decimal = value }

                    Color ->
                        { model | color = value }

                    Borders ->
                        { model | borders = value }

                    Glyphs ->
                        { model | glyphs = value }
                )

        SetToggle toggle value ->
            changed
                (case toggle of
                    Header ->
                        { model | header = value }

                    Lossy ->
                        { model | lossy = value }

                    Plain ->
                        { model | plain = value }
                )

        SetColumn index setting value ->
            let
                old =
                    Dict.get index model.overrides |> Maybe.withDefault { width = "", alignment = "inherit", overflow = "inherit" }

                next =
                    case setting of
                        Width ->
                            { old | width = value }

                        Alignment ->
                            { old | alignment = value }

                        Overflow ->
                            { old | overflow = value }

                        _ ->
                            old
            in
            changed { model | overrides = Dict.insert index next model.overrides }

        SetPage page ->
            ( { model | page = max 0 (min page ((max 1 model.columns - 1) // 8)) }, Cmd.none )

        Inspect token ->
            if token /= model.token || not model.ready then
                ( model, Cmd.none )

            else if model.input == "" && model.source == Nothing then
                ( { model | inspecting = False, detected = Nothing, rows = 0, columns = 0 }, Cmd.none )

            else
                ( { model | inspecting = True }, request "inspect" model )

        Convert ->
            if canConvert model then
                ( { model | busy = True, result = Nothing, error = "", copyStatus = "" }, request "convert" model )

            else
                ( model, Cmd.none )

        Received reply ->
            if reply.kind == "ready" then
                if reply.ok then
                    if model.ready then
                        ( { model | legend = reply.display }, Cmd.none )

                    else
                        ( { model | ready = True, inspecting = True, legend = reply.display }, request "inspect" model )

                else
                    ( { model | ready = False, error = reply.error }, Cmd.none )

            else if reply.token /= model.token then
                ( model, Cmd.none )

            else
                case reply.kind of
                    "inspect" ->
                        ( { model
                            | inspecting = False
                            , detected =
                                if reply.ok then
                                    parseFormat reply.source

                                else
                                    Nothing
                            , rows = reply.rows
                            , columns = reply.columns
                            , error = reply.error
                            , page = min model.page ((max 1 reply.columns - 1) // 8)
                            , overrides = Dict.filter (\index _ -> index < reply.columns) model.overrides
                          }
                        , Cmd.none
                        )

                    "convert" ->
                        ( { model
                            | busy = False
                            , error = reply.error
                            , result =
                                if reply.ok then
                                    Just { display = reply.display, bytes = reply.bytes }

                                else
                                    Nothing
                          }
                        , Cmd.none
                        )

                    "copy" ->
                        ( { model
                            | copyStatus =
                                if reply.ok then
                                    "Copied!"

                                else
                                    "Copy failed"
                            , error = reply.error
                          }
                        , Process.sleep 2000 |> Task.perform (\_ -> ResetCopy model.token)
                        )

                    "download" ->
                        ( { model | error = reply.error }, Cmd.none )

                    _ ->
                        ( model, Cmd.none )

        Copy ->
            ( model, action "copy" model )

        Download ->
            ( model, action "download" model )

        ResetCopy token ->
            if token == model.token then
                ( { model | copyStatus = "" }, Cmd.none )

            else
                ( model, Cmd.none )

        Example ->
            changed { model | input = sample, source = Nothing, header = True, lossy = False, borders = "auto", overrides = Dict.empty, page = 0 }

        Clear ->
            changed { model | input = "", detected = Nothing, rows = 0, columns = 0, overrides = Dict.empty }


canConvert : Model -> Bool
canConvert model =
    model.ready
        && not model.busy
        && not model.inspecting
        && model.error
        == ""
        && (model.input /= "" || model.source /= Nothing)
        && (not (visual (effectiveSource model)) || model.lossy)


action : String -> Model -> Cmd Msg
action kind model =
    toEngine (J.object [ ( "kind", J.string kind ), ( "token", J.int model.token ) ])


inputGlyphs : Model -> String
inputGlyphs model =
    if model.source /= Nothing && not (visual model.source) then
        ""

    else
        case model.borders of
            "ascii" ->
                "+,+,+,+,+,+,+,+,+,-,|"

            "unicode" ->
                "┌,┬,┐,├,┼,┤,└,┴,┘,─,│"

            "rounded" ->
                "╭,┬,╮,├,┼,┤,╰,┴,╯,─,│"

            "custom" ->
                model.glyphs

            _ ->
                ""


request : String -> Model -> Cmd Msg
request kind model =
    let
        column ( index, option ) =
            J.object [ ( "index", J.int index ), ( "width", J.string option.width ), ( "alignment", J.string option.alignment ), ( "overflow", J.string option.overflow ) ]
    in
    toEngine
        (J.object
            [ ( "kind", J.string kind )
            , ( "token", J.int model.token )
            , ( "input", J.string model.input )
            , ( "options"
              , J.object
                    [ ( "from", J.string (model.source |> Maybe.map formatName |> Maybe.withDefault "auto") )
                    , ( "to", J.string (formatName model.destination) )
                    , ( "header", J.bool model.header )
                    , ( "allowLossy", J.bool model.lossy )
                    , ( "plain", J.bool model.plain )
                    , ( "width", J.string model.width )
                    , ( "alignment", J.string model.alignment )
                    , ( "overflow", J.string model.overflow )
                    , ( "decimal", J.string model.decimal )
                    , ( "color", J.string model.color )
                    , ( "glyphs", J.string (inputGlyphs model) )
                    , ( "columns", J.list column (Dict.toList model.overrides) )
                    ]
              )
            ]
        )


select : String -> String -> String -> List ( String, String ) -> (String -> Msg) -> Bool -> Html Msg
select id caption value choices message disabled =
    H.div [ A.class "field" ]
        [ H.label [ A.for id ] [ H.text caption ]
        , H.select [ A.id id, A.value value, E.onInput message, A.disabled disabled ]
            (List.map (\( key, label ) -> H.option [ A.value key ] [ H.text label ]) choices)
        ]


check : String -> Bool -> Toggle -> Model -> Html Msg
check caption checked toggle _ =
    H.label [ A.class "check" ]
        [ H.input [ A.type_ "checkbox", A.checked checked, E.onCheck (SetToggle toggle) ] []
        , H.span [] [ H.text caption ]
        ]


alignChoices : List ( String, String )
alignChoices =
    [ ( "auto", "Auto" ), ( "left", "Left" ), ( "right", "Right" ), ( "center", "Center" ) ]


overflowChoices : List ( String, String )
overflowChoices =
    [ ( "auto", "Smart clipping" )
    , ( "suffix-ellipsis", "Keep start + ellipsis" )
    , ( "prefix-ellipsis", "Keep end + ellipsis" )
    , ( "truncate-right", "Keep start" )
    , ( "truncate-left", "Keep end" )
    ]


view : Model -> Html Msg
view model =
    let
        choices =
            List.map (\( _, key, label ) -> ( key, label )) names

        sourceName =
            model.source |> Maybe.map formatName |> Maybe.withDefault "auto"

        output =
            model.result |> Maybe.map .display |> Maybe.withDefault ""

        hasResult =
            model.result /= Nothing && not model.busy

        detected =
            if not model.ready then
                "Loading converter…"

            else if model.inspecting then
                "Checking input…"

            else
                model.detected |> Maybe.map (\f -> formatLabel f ++ " identified") |> Maybe.withDefault "Ready for your table"
    in
    H.div [ A.class "shell" ]
        [ H.header [ A.class "site-header" ]
            [ H.a [ A.href "./", A.class "brand", A.attribute "aria-label" "table home" ]
                [ H.span [ A.class "brand-mark", A.attribute "aria-hidden" "true" ] (List.repeat 6 (H.i [] [])), H.span [] [ H.text "table" ] ]
            , H.a [ A.class "github-link", A.href "https://github.com/pmarreck/table", A.target "_blank", A.rel "noopener noreferrer" ] [ H.text "View on GitHub ↗" ]
            ]
        , H.main_ []
            [ H.section [ A.class "intro" ]
                [ H.div []
                    [ H.p [ A.class "eyebrow" ] [ H.text "A UNIVERSAL TABLE CONVERTER" ]
                    , H.h1 [] [ H.text "Tables, translated." ]
                    , H.p [ A.class "lede" ] [ H.text "Move between data, documents and terminal tables. A cleaner format is a paste away." ]
                    ]
                , H.div [ A.class "privacy" ] [ H.span [ A.class "status-dot" ] [], H.text "Your data stays on this device" ]
                ]
            , H.form [ E.onSubmit Convert, A.class "converter" ]
                [ H.div [ A.class "conversion-bar" ]
                    [ select "source-format" "Input format" sourceName (( "auto", "Auto-detect" ) :: choices) SetSource False
                    , H.span [ A.class "direction", A.attribute "aria-hidden" "true" ] [ H.text "→" ]
                    , select "output-format" "Output format" (formatName model.destination) choices SetDestination False
                    , H.button [ A.type_ "submit", A.class "primary convert", A.disabled (not (canConvert model)) ]
                        [ H.text
                            (if model.busy then
                                "Converting…"

                             else
                                "Convert table"
                            )
                        , H.span [ A.attribute "aria-hidden" "true" ] [ H.text " ↗" ]
                        ]
                    ]
                , H.div [ A.class "workspace" ]
                    [ H.section [ A.class "editor-card" ]
                        [ H.div [ A.class "card-heading" ] [ H.h2 [] [ H.text "Source" ], H.span [ A.class "fingerprint", A.attribute "aria-live" "polite" ] [ H.text detected ] ]
                        , H.label [ A.for "source-input", A.class "sr-only" ] [ H.text "Source table" ]
                        , H.textarea [ A.id "source-input", A.value model.input, E.onInput EditInput, A.spellcheck False, A.attribute "wrap" "off", A.attribute "autocapitalize" "off", A.placeholder "Paste a table here…" ] []
                        , H.div [ A.class "editor-footer" ]
                            [ H.div [ A.class "text-actions" ] [ H.button [ A.type_ "button", E.onClick Example ] [ H.text "Load example" ], H.button [ A.type_ "button", E.onClick Clear ] [ H.text "Clear" ] ]
                            , H.span [] [ H.text (String.fromInt (String.length model.input) ++ " characters") ]
                            ]
                        ]
                    , H.section [ A.class "editor-card result-card" ]
                        [ H.div [ A.class "card-heading" ]
                            [ H.h2 [] [ H.text "Result" ]
                            , H.div [ A.class "result-actions" ]
                                [ H.button [ A.type_ "button", A.class "download", A.disabled (not hasResult), E.onClick Download, A.title "Download the original output bytes", A.attribute "aria-label" "Download result" ] [ H.text "↓" ]
                                , H.button [ A.type_ "button", A.class "copy", A.disabled (not hasResult), E.onClick Copy ]
                                    [ H.text
                                        (if model.copyStatus /= "" then
                                            model.copyStatus

                                         else if model.destination == Ir then
                                            "Copy raw IR"

                                         else
                                            "Copy result"
                                        )
                                    ]
                                ]
                            ]
                        , H.label [ A.for "result-output", A.class "sr-only" ] [ H.text "Converted table" ]
                        , H.textarea [ A.id "result-output", A.value output, A.readonly True, A.spellcheck False, A.attribute "wrap" "off", A.placeholder "Your converted table appears here." ] []
                        , H.div [ A.class "editor-footer", A.attribute "aria-live" "polite" ]
                            [ H.span []
                                [ H.text
                                    (if hasResult then
                                        String.fromInt model.rows ++ " rows · " ++ String.fromInt model.columns ++ " columns"

                                     else
                                        "Waiting for conversion"
                                    )
                                ]
                            , H.span [] [ H.text (model.result |> Maybe.map (\r -> String.fromInt r.bytes ++ " bytes") |> Maybe.withDefault "") ]
                            ]
                        ]
                    ]
                , if model.error /= "" then
                    H.div [ A.class "error", A.attribute "role" "alert" ] [ H.text model.error ]

                  else
                    H.text ""
                , if model.destination == Ir then
                    H.aside [ A.class "ir-notice" ]
                        [ H.strong [] [ H.text "Printable view, original bytes." ]
                        , H.p [] [ H.text "IR uses non-printing FS, GS, RS and US separators. The preview shows printable-binary glyphs; copy and download use the raw IR. Some apps hide or alter control characters. Download is safest for exact bytes." ]
                        , H.div [ A.id "ir-legend", A.class "ir-legend" ] [ H.text model.legend ]
                        ]

                  else if model.destination == Ansi then
                    H.p [ A.class "hint output-note" ] [ H.text "The preview makes ANSI escape codes visible. Copy and download retain the original styling codes." ]

                  else
                    H.text ""
                , H.div [ A.class "format-options" ]
                    [ select "header-mode"
                        "CSV / TSV header"
                        (if model.header then
                            "header"

                         else
                            "data"
                        )
                        [ ( "header", "First row is a header" ), ( "data", "All rows are data" ) ]
                        (\s -> SetToggle Header (s == "header"))
                        (effectiveSource model /= Just Csv && effectiveSource model /= Just Tsv)
                    , if visual (effectiveSource model) then
                        H.div [ A.class "lossy" ] [ check "Accept possible loss from visual input" model.lossy Lossy model, H.p [ A.class "hint" ] [ H.text "Rendered tables may already be clipped, padded or sanitized." ] ]

                      else
                        H.text ""
                    ]
                , optionsView model
                ]
            ]
        , H.footer [ A.class "site-footer" ]
            [ H.span [] [ H.text "Built with Elm + WebAssembly. Processed locally." ]
            , H.div [] [ H.a [ A.href "https://github.com/pmarreck/table" ] [ H.text "Source code" ], H.a [ A.href "./LICENSES.txt" ] [ H.text "Licenses" ] ]
            ]
        ]


optionsView : Model -> Html Msg
optionsView model =
    let
        rendering =
            visual (Just model.destination)

        inputBorders =
            visual (effectiveSource model) || (model.source == Nothing && model.detected == Nothing)
    in
    if not rendering && not inputBorders then
        H.text ""

    else
        H.details [ A.class "options" ]
            [ H.summary [] [ H.span [] [ H.text "Conversion options" ], H.span [ A.class "summary-hint" ] [ H.text "Layout, clipping and borders" ] ]
            , if rendering then
                H.div [ A.class "options-grid" ]
                    [ H.div [ A.class "field" ] [ H.label [ A.for "table-width" ] [ H.text "Table width" ], H.input [ A.id "table-width", A.type_ "number", A.min "1", A.max "10000", A.value model.width, E.onInput (SetSetting Width) ] [], H.small [] [ H.text "Maximum width in display cells" ] ]
                    , select "alignment" "Default alignment" model.alignment alignChoices (SetSetting Alignment) False
                    , select "clipping" "Clipping" model.overflow overflowChoices (SetSetting Overflow) False
                    , select "decimal" "Decimal separator" model.decimal [ ( ".", "Period (1.25)" ), ( ",", "Comma (1,25)" ), ( "٫", "Arabic (1٫25)" ) ] (SetSetting Decimal) False
                    , select "color" "Header color" model.color [ ( "auto", "Auto" ), ( "always", "Always" ), ( "never", "Never" ) ] (SetSetting Color) False
                    , H.div [ A.class "plain-option" ] [ check "Minimal layout (no borders)" model.plain Plain model, H.small [] [ H.text "Auto color exports unstyled text in the browser." ] ]
                    ]

              else
                H.text ""
            , if inputBorders then
                H.div [ A.class "border-options" ]
                    [ select "input-borders" "Input borders" model.borders [ ( "auto", "Auto-detect" ), ( "ascii", "ASCII" ), ( "unicode", "Unicode" ), ( "rounded", "Rounded" ), ( "custom", "Custom glyphs" ) ] (SetSetting Borders) False
                    , if model.borders == "custom" then
                        H.div [ A.class "field wide" ] [ H.label [ A.for "custom-glyphs" ] [ H.text "Custom input glyphs" ], H.input [ A.id "custom-glyphs", A.value model.glyphs, E.onInput (SetSetting Glyphs) ] [], H.small [] [ H.text "11 comma-separated glyphs: top, middle and bottom junctions, then horizontal and vertical." ] ]

                      else
                        H.text ""
                    ]

              else
                H.text ""
            , if rendering && model.columns > 0 then
                columnsView model

              else
                H.text ""
            , if rendering then
                H.p [ A.class "hint render-note" ] [ H.text "Visual output can clip, pad or sanitize cell contents. Use CSV, TSV or IR to keep the data representation." ]

              else
                H.text ""
            ]


columnsView : Model -> Html Msg
columnsView model =
    let
        row index =
            let
                column =
                    Dict.get index model.overrides |> Maybe.withDefault { width = "", alignment = "inherit", overflow = "inherit" }

                prefix =
                    "column-" ++ String.fromInt (index + 1)
            in
            H.div [ A.class "column-row" ]
                [ H.strong [] [ H.text ("Column " ++ String.fromInt (index + 1)) ]
                , H.div [ A.class "column-width" ]
                    [ select (prefix ++ "-width-mode")
                        "Width"
                        (if column.width == "" then
                            "auto"

                         else
                            "fixed"
                        )
                        [ ( "auto", "Auto width" ), ( "fixed", "Fixed width" ) ]
                        (\s ->
                            SetColumn index
                                Width
                                (if s == "fixed" then
                                    "12"

                                 else
                                    ""
                                )
                        )
                        False
                    , if column.width /= "" then
                        H.input [ A.type_ "number", A.min "1", A.max "10000", A.value column.width, A.attribute "aria-label" ("Column " ++ String.fromInt (index + 1) ++ " width"), E.onInput (SetColumn index Width) ] []

                      else
                        H.text ""
                    ]
                , select (prefix ++ "-align") "Alignment" column.alignment (( "inherit", "Use default" ) :: alignChoices) (SetColumn index Alignment) False
                , select (prefix ++ "-clip") "Clipping" column.overflow (( "inherit", "Use default" ) :: overflowChoices) (SetColumn index Overflow) False
                ]

        start =
            model.page * 8
    in
    H.div [ A.class "column-options" ]
        [ H.div [ A.class "column-title" ] [ H.h3 [] [ H.text "Per-column overrides" ], H.span [] [ H.text "Defaults apply unless overridden" ] ]
        , H.div [] (List.map row (List.range start (min (model.columns - 1) (start + 7))))
        , if model.columns > 8 then
            H.div [ A.class "pagination" ] [ H.button [ A.type_ "button", A.disabled (model.page == 0), E.onClick (SetPage (model.page - 1)) ] [ H.text "Previous" ], H.span [] [ H.text (String.fromInt (start + 1) ++ "–" ++ String.fromInt (min model.columns (start + 8)) ++ " of " ++ String.fromInt model.columns) ], H.button [ A.type_ "button", A.disabled (start + 8 >= model.columns), E.onClick (SetPage (model.page + 1)) ] [ H.text "Next" ] ]

          else
            H.text ""
        ]
