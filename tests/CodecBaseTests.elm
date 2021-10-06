module CodecBaseTests exposing (suite)

import Dict
import Expect
import Fuzz exposing (Fuzzer)
import Json.Decode as JD
import Json.Encode as JE
import Set
import Test exposing (Test, describe, fuzz, test)
import TsJson.Codec as Codec exposing (Codec)
import TsJson.Decode
import TsJson.Encode
import TsJson.Type
import TsType


suite : Test
suite =
    describe "Testing roundtrips"
        [ describe "Basic" basicTests
        , describe "Containers" containersTests
        , describe "Object" objectTests
        , describe "Custom" customTests
        , describe "bimap" bimapTests
        , describe "maybe" maybeTests
        , describe "succeed"
            [ test "roundtrips"
                (\_ ->
                    Codec.succeed 632
                        |> (\d -> JD.decodeString (Codec.decoder d |> TsJson.Decode.decoder) "{}")
                        |> Expect.equal (Ok 632)
                )
            ]
        , describe "recursive" recursiveTests
        , describe "map,andThen" mapAndThenTests
        ]


roundtrips : Fuzzer a -> Codec a -> Test
roundtrips fuzzer codec =
    fuzz fuzzer "is a roundtrip" <|
        \value ->
            let
                encoded =
                    value
                        |> TsJson.Encode.encoder (Codec.encoder codec)
            in
            encoded
                |> (Codec.decoder codec
                        |> TsJson.Decode.decoder
                        |> JD.decodeValue
                   )
                |> Result.mapError JD.errorToString
                |> Expect.all
                    [ Expect.equal (Ok value)
                    , \_ ->
                        Expect.equal
                            (codec |> Codec.encoder |> TsJson.Encode.tsType |> TsJson.Type.toTypeScript)
                            (codec |> Codec.decoder |> TsJson.Decode.tsType |> TsJson.Type.toTypeScript)
                    ]


roundtripsWithDifferentAnnotations : Fuzzer a -> Codec a -> Test
roundtripsWithDifferentAnnotations fuzzer codec =
    fuzz fuzzer "is a roundtrip" <|
        \value ->
            value
                |> TsJson.Encode.encoder (Codec.encoder codec)
                |> (Codec.decoder codec
                        |> TsJson.Decode.decoder
                        |> JD.decodeValue
                   )
                |> Expect.equal (Ok value)


roundtripsWithin : Fuzzer Float -> Codec Float -> Test
roundtripsWithin fuzzer codec =
    fuzz fuzzer "is a roundtrip" <|
        \value ->
            value
                |> TsJson.Encode.encoder (Codec.encoder codec)
                |> (Codec.decoder codec
                        |> TsJson.Decode.decoder
                        |> JD.decodeValue
                   )
                |> Result.withDefault -999.1234567
                |> Expect.within (Expect.Relative 0.000001) value


basicTests : List Test
basicTests =
    [ describe "Codec.string"
        [ roundtrips Fuzz.string Codec.string
        ]
    , describe "Codec.int"
        [ roundtrips Fuzz.int Codec.int
        ]
    , describe "Codec.float"
        [ roundtrips Fuzz.float Codec.float
        ]
    , describe "Codec.bool"
        [ roundtrips Fuzz.bool Codec.bool
        ]
    ]


containersTests : List Test
containersTests =
    [ describe "Codec.array"
        [ roundtrips (Fuzz.array Fuzz.int) (Codec.array Codec.int)
        ]
    , describe "Codec.list"
        [ roundtrips (Fuzz.list Fuzz.int) (Codec.list Codec.int)
        ]
    , describe "Codec.dict"
        [ roundtrips
            (Fuzz.map2 Tuple.pair Fuzz.string Fuzz.int
                |> Fuzz.list
                |> Fuzz.map Dict.fromList
            )
            (Codec.dict Codec.int)
        ]
    , describe "Codec.set"
        [ roundtrips
            (Fuzz.list Fuzz.int |> Fuzz.map Set.fromList)
            (Codec.set Codec.int)
        ]
    , describe "Codec.tuple"
        [ roundtrips
            (Fuzz.tuple ( Fuzz.int, Fuzz.int ))
            (Codec.tuple Codec.int Codec.int)
        ]
    ]


objectTests : List Test
objectTests =
    [ describe "with 0 fields"
        [ roundtripsWithDifferentAnnotations (Fuzz.constant {})
            (Codec.object {}
                |> Codec.buildObject
            )
        ]
    , describe "with 1 field"
        [ roundtrips (Fuzz.map (\i -> { fname = i }) Fuzz.int)
            (Codec.object (\i -> { fname = i })
                |> Codec.field "fname" .fname Codec.int
                |> Codec.buildObject
            )
        ]
    , describe "with 2 fields"
        [ roundtrips
            (Fuzz.map2
                (\a b ->
                    { a = a
                    , b = b
                    }
                )
                Fuzz.int
                Fuzz.int
            )
            (Codec.object
                (\a b ->
                    { a = a
                    , b = b
                    }
                )
                |> Codec.field "a" .a Codec.int
                |> Codec.field "b" .b Codec.int
                |> Codec.buildObject
            )
        ]
    , describe "nullableField vs maybeField" <|
        let
            nullableCodec =
                Codec.object
                    (\f -> { f = f })
                    |> Codec.nullableField "f" .f Codec.int
                    |> Codec.buildObject

            maybeCodec =
                Codec.object
                    (\f -> { f = f })
                    |> Codec.maybeField "f" .f Codec.int
                    |> Codec.buildObject
        in
        [ test "a nullableField is required" <|
            \_ ->
                "{}"
                    |> decodeString nullableCodec
                    |> (\r ->
                            case r of
                                Ok _ ->
                                    Expect.fail "Should have failed"

                                Err _ ->
                                    Expect.pass
                       )
        , test "a nullableField produces a field with a null value on encoding Nothing" <|
            \_ ->
                { f = Nothing }
                    |> encodeToString nullableCodec
                    |> Expect.equal "{\"f\":null}"
        , test "a maybeField is optional" <|
            \_ ->
                "{}"
                    |> decodeString maybeCodec
                    |> Expect.equal (Ok { f = Nothing })
        , test "a maybeField doesn't produce a field on encoding Nothing" <|
            \_ ->
                { f = Nothing }
                    |> encodeToString maybeCodec
                    |> Expect.equal "{}"
        ]
    ]


encodeToString : Codec input -> (input -> String)
encodeToString codec =
    (codec
        |> Codec.encoder
        |> TsJson.Encode.encoder
    )
        >> JE.encode 0


decodeString : Codec a -> String -> Result JD.Error a
decodeString codec =
    Codec.decoder codec
        |> TsJson.Decode.decoder
        |> JD.decodeString


type Newtype a
    = Newtype a


customTests : List Test
customTests =
    [ describe "with 1 ctor, 0 args"
        [ roundtrips (Fuzz.constant ())
            (Codec.custom Nothing
                (\f v ->
                    case v of
                        () ->
                            f
                )
                |> Codec.variant0 "()" ()
                |> Codec.buildCustom
            )
        ]
    , describe "with 1 ctor, 1 arg"
        [ roundtrips (Fuzz.map Newtype Fuzz.int)
            (Codec.custom Nothing
                (\f v ->
                    case v of
                        Newtype a ->
                            f a
                )
                |> Codec.positionalVariant1 "Newtype" Newtype Codec.int
                |> Codec.buildCustom
            )
        ]
    , describe "with 2 ctors, 0,1 args" <|
        let
            match fnothing fjust value =
                case value of
                    Nothing ->
                        fnothing

                    Just v ->
                        fjust v

            codec =
                Codec.custom Nothing match
                    |> Codec.variant0 "Nothing" Nothing
                    |> Codec.positionalVariant1 "Just" Just Codec.int
                    |> Codec.buildCustom

            fuzzers =
                [ ( "1st ctor", Fuzz.constant Nothing )
                , ( "2nd ctor", Fuzz.map Just Fuzz.int )
                ]
        in
        fuzzers
            |> List.map
                (\( name, fuzz ) ->
                    describe name
                        [ roundtrips fuzz codec ]
                )
    , describe "with 2 ctors, 0,2 args" <|
        let
            match : TsJson.Encode.UnionEncodeValue -> (Int -> Int -> TsJson.Encode.UnionEncodeValue) -> Maybe ( Int, Int ) -> TsJson.Encode.UnionEncodeValue
            match fnothing fjust value =
                case value of
                    Nothing ->
                        fnothing

                    Just ( v1, v2 ) ->
                        fjust v1 v2

            codec : Codec (Maybe ( Int, Int ))
            codec =
                Codec.custom Nothing match
                    |> Codec.variant0 "Nothing" Nothing
                    |> Codec.positionalVariant2 "Just" (\first second -> Just ( first, second )) Codec.int Codec.int
                    |> Codec.buildCustom
        in
        [ ( "1st ctor", Fuzz.constant Nothing )
        , ( "2nd ctor", Fuzz.map2 (\a b -> Just ( a, b )) Fuzz.int Fuzz.int )
        ]
            |> roundtripsTest "codec type"
                codec
                """{ args : [ number, number ]; tag : "Just" } | { tag : "Nothing" }"""
    , describe "with 3 ctors, 0,3 args" <|
        let
            codec : Codec MyCustomType
            codec =
                Codec.custom Nothing
                    (\fSingle fTriple value ->
                        case value of
                            Single v1 ->
                                fSingle v1

                            Triple v1 v2 v3 ->
                                fTriple v1 v2 v3
                    )
                    |> Codec.positionalVariant1 "Single" Single Codec.int
                    |> Codec.positionalVariant3 "Triple" (\v1 v2 v3 -> Triple v1 v2 v3) Codec.int Codec.int Codec.int
                    |> Codec.buildCustom
        in
        [ ( "1st ctor", Fuzz.map Single Fuzz.int )
        , ( "2nd ctor", Fuzz.map3 Triple Fuzz.int Fuzz.int Fuzz.int )
        ]
            |> roundtripsTest "codec type"
                codec
                """{ args : [ number, number, number ]; tag : "Triple" } | { args : [ number ]; tag : "Single" }"""
    ]


type MyCustomType
    = Single Int
    | Triple Int Int Int


roundtripsTest :
    String
    -> Codec value
    -> String
    -> List ( String, Fuzzer value )
    -> List Test
roundtripsTest testName codec expectedTsType fuzzers =
    (test testName <|
        \() ->
            codec
                |> Codec.tsType
                |> TsType.toString
                |> Expect.equal expectedTsType
    )
        :: (fuzzers
                |> List.map
                    (\( name, fuzz ) ->
                        describe name
                            [ roundtrips fuzz codec ]
                    )
           )


bimapTests : List Test
bimapTests =
    [ roundtripsWithin Fuzz.float <|
        Codec.map
            (\x -> x * 2)
            (\x -> x / 2)
            Codec.float
    ]


maybeTests : List Test
maybeTests =
    [ describe "single"
        [ roundtripsWithDifferentAnnotations
            (Fuzz.oneOf
                [ Fuzz.constant Nothing
                , Fuzz.map Just Fuzz.int
                ]
            )
          <|
            Codec.maybe Codec.int
        ]

    {-
       This is a known limitation: using null as Nothing and identity as Just means that nesting two maybes squashes Just Nothing with Nothing
       , describe "double"
          [ roundtrips
              (Fuzz.oneOf
                  [ Fuzz.constant Nothing
                  , Fuzz.constant <| Just Nothing
                  , Fuzz.map (Just << Just) Fuzz.int
                  ]
              )
            <|
              Codec.maybe <|
                  Codec.maybe Codec.int
          ]
    -}
    ]


recursiveTests : List Test
recursiveTests =
    [ ( "list", Fuzz.list Fuzz.int ) ]
        |> roundtripsTest "recursive list"
            (Codec.recursive
                (\c ->
                    Codec.custom Nothing
                        (\fempty fcons value ->
                            case value of
                                [] ->
                                    fempty

                                x :: xs ->
                                    fcons x xs
                        )
                        |> Codec.variant0 "[]" []
                        |> Codec.positionalVariant2 "(::)" (::) Codec.int c
                        |> Codec.buildCustom
                )
            )
            """{ args : [ number, JsonValue ]; tag : "(::)" } | { tag : "[]" }"""


mapAndThenTests : List Test
mapAndThenTests =
    [ describe "Codec.map"
        [ roundtrips (Fuzz.intRange -10000 10000) <|
            Codec.map (\x -> x - 1) (\x -> x + 1) Codec.int
        ]
    ]