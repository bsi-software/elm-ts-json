module TsJson.Codec exposing
    ( Codec, Value, Error
    , Decoder, decoder, decodeString, decodeValue
    , encoder, encodeToString, encodeToValue
    , string, bool, int, float
    , maybe, list, array, dict, set, tuple, triple
    , ObjectCodec, object, field, maybeField, nullableField, buildObject
    , CustomCodec, custom, variant0, variant1, buildCustom
    , oneOf
    , map
    , succeed, fail, value, build
    , tsType
    ,  variant2
       --recursive, andThen, lazy,

    )

{-| A `Codec a` contain a JSON `Decoder a` and the corresponding `a -> Value` encoder.


# Definition

@docs Codec, Value, Error


# Decode

@docs Decoder, decoder, decodeString, decodeValue


# Encode

@docs encoder, encodeToString, encodeToValue


# Primitives

@docs string, bool, int, float


# Data Structures

-- @ docs maybe, list, array, dict, set, tuple, triple, result

@docs maybe, list, array, dict, set, tuple, triple


# Object Primitives

@docs ObjectCodec, object, field, maybeField, nullableField, buildObject


# Custom Types

-- @ docs CustomCodec, custom, variant0, variant1, variant2, variant3, variant4, variant5, variant6, variant7, variant8, buildCustom

@docs CustomCodec, custom, variant0, variant1, buildCustom


# Inconsistent structure

@docs oneOf


# Mapping

@docs map


# Fancy Codecs

-- @ docs succeed, recursive, fail, andThen, lazy, value, build

@docs succeed, fail, value, build

@docs tsType

-}

import Array exposing (Array)
import Dict exposing (Dict)
import Internal.TsJsonType as TsType exposing (TsType)
import Json.Decode
import Json.Encode
import Set exposing (Set)
import TsJson.Decode as JD
import TsJson.Encode as JE exposing (Encoder, Property)



-- DEFINITION


{-| A value that knows how to encode and decode JSON values.
-}
type Codec a
    = Codec
        { encoder : JE.Encoder a
        , decoder : Decoder a
        }


{-| Represents a JavaScript value.
-}
type alias Value =
    Json.Encode.Value


{-| A structured error describing exactly how the decoder failed. You can use
this to create more elaborate visualizations of a decoder problem. For example,
you could show the entire JSON object and show the part causing the failure in
red.
-}
type alias Error =
    Json.Decode.Error



-- DECODE


{-| A value that knows how to decode JSON values.
-}
type alias Decoder a =
    JD.Decoder a


{-| Extracts the `Decoder` contained inside the `Codec`.
-}
decoder : Codec a -> Decoder a
decoder (Codec m) =
    m.decoder


{-| Parse the given string into a JSON value and then run the `Codec` on it.
This will fail if the string is not well-formed JSON or if the `Codec`
fails for some reason.
-}
decodeString : Codec a -> String -> Result Error a
decodeString codec =
    Json.Decode.decodeString (decoder codec |> JD.decoder)


{-| Run a `Codec` to decode some JSON `Value`. You can send these JSON values
through ports, so that is probably the main time you would use this function.
-}
decodeValue : Codec a -> Value -> Result Error a
decodeValue codec =
    Json.Decode.decodeValue (decoder codec |> JD.decoder)



-- ENCODE


{-| Extracts the encoding function contained inside the `Codec`.
-}
encoder : Codec a -> JE.Encoder a
encoder (Codec m) =
    m.encoder


{-| Convert a value into a prettified JSON string. The first argument specifies
the amount of indentation in the result string.
-}
encodeToString : Int -> Codec a -> (a -> String)
encodeToString indentation codec =
    encodeToValue codec >> Json.Encode.encode indentation


{-| Convert a value into a Javascript `Value`.
-}
encodeToValue : Codec a -> a -> Value
encodeToValue codec =
    codec
        |> encoder
        |> JE.encoder



-- BASE


{-| Build your own custom `Codec`.
Useful if you have pre-existing `Decoder`s you need to use.
-}
build : JE.Encoder a -> Decoder a -> Codec a
build encoder_ decoder_ =
    Codec
        { encoder = encoder_
        , decoder = decoder_
        }


{-| `Codec` between a JSON string and an Elm `String`
-}
string : Codec String
string =
    build JE.string JD.string


{-| `Codec` between a JSON boolean and an Elm `Bool`
-}
bool : Codec Bool
bool =
    build JE.bool JD.bool


{-| `Codec` between a JSON number and an Elm `Int`
-}
int : Codec Int
int =
    build JE.int JD.int


{-| `Codec` between a JSON number and an Elm `Float`
-}
float : Codec Float
float =
    build JE.float JD.float



-- DATA STRUCTURES


composite : (JE.Encoder b -> JE.Encoder a) -> (Decoder b -> Decoder a) -> Codec b -> Codec a
composite enc dec (Codec codec) =
    Codec
        { encoder = enc codec.encoder
        , decoder = dec codec.decoder
        }


{-| Represents an optional value.
-}
maybe : Codec a -> Codec (Maybe a)
maybe codec =
    Codec
        { decoder = JD.maybe <| decoder codec
        , encoder = JE.maybe <| encoder codec
        }


{-| `Codec` between a JSON array and an Elm `List`.
-}
list : Codec a -> Codec (List a)
list =
    composite JE.list JD.list


{-| `Codec` between a JSON array and an Elm `Array`.
-}
array : Codec a -> Codec (Array a)
array =
    composite JE.array JD.array


{-| `Codec` between a JSON object and an Elm `Dict`.
-}
dict : Codec a -> Codec (Dict String a)
dict =
    composite
        (JE.dict identity)
        JD.dict


{-| `Codec` between a JSON array and an Elm `Set`.
-}
set : Codec comparable -> Codec (Set comparable)
set =
    composite
        (JE.map Set.toList << JE.list)
        (JD.map Set.fromList << JD.list)


{-| `Codec` between a JSON array of length 2 and an Elm `Tuple`.
-}
tuple : Codec a -> Codec b -> Codec ( a, b )
tuple m1 m2 =
    Codec
        { encoder =
            JE.tuple
                (encoder m1)
                (encoder m2)
        , decoder =
            JD.tuple
                (decoder m1)
                (decoder m2)
        }


{-| `Codec` between a JSON array of length 3 and an Elm triple.
-}
triple : Codec a -> Codec b -> Codec c -> Codec ( a, b, c )
triple m1 m2 m3 =
    Codec
        { encoder =
            JE.triple
                (encoder m1)
                (encoder m2)
                (encoder m3)
        , decoder =
            JD.triple
                (decoder m1)
                (decoder m2)
                (decoder m3)
        }



--{-| `Codec` for `Result` values.
---}
--result : Codec error -> Codec value -> Codec (Result error value)
--result errorCodec valueCodec =
--    custom
--        (\ferr fok v ->
--            case v of
--                Err err ->
--                    ferr err
--
--                Ok ok ->
--                    fok ok
--        )
--        |> variant1 "Err" Err errorCodec
--        |> variant1 "Ok" Ok valueCodec
--        |> buildCustom
-- OBJECTS


{-| A partially built `Codec` for an object.
-}
type ObjectCodec a b
    = ObjectCodec
        { encoder : List (Property a)
        , decoder : Decoder b
        }


{-| Start creating a `Codec` for an object. You should pass the main constructor as argument.
If you don't have one (for example it's a simple type with no name), you should pass a function that given the field values builds an object.

Example with constructor:

    type alias Point =
        { x : Float
        , y : Float
        }

    pointCodec : Codec Point
    pointCodec =
        Codec.object Point
            |> Codec.field "x" .x Codec.float
            |> Codec.field "y" .y Codec.float
            |> Codec.buildObject

Example without constructor:

    pointCodec : Codec { x : Int, y : Bool }
    pointCodec =
        Codec.object (\x y -> { x = x, y = y })
            |> Codec.field "x" .x Codec.int
            |> Codec.field "y" .y Codec.bool
            |> Codec.buildObject

-}
object : b -> ObjectCodec a b
object ctor =
    ObjectCodec
        { encoder = []
        , decoder = JD.succeed ctor
        }


{-| Specify the name, getter and `Codec` for a field.

The name is only used as the field name in the resulting JSON, and has no impact on the Elm side.

-}
field : String -> (a -> f) -> Codec f -> ObjectCodec a (f -> b) -> ObjectCodec a b
field name getter codec (ObjectCodec ocodec) =
    ObjectCodec
        { encoder =
            JE.required name getter (encoder codec)
                :: ocodec.encoder
        , decoder = JD.map2 (\f x -> f x) ocodec.decoder (JD.field name (decoder codec))
        }


{-| Specify the name getter and `Codec` for an optional field.

This is particularly useful for evolving your `Codec`s.

If the field is not present in the input then it gets decoded to `Nothing`.
If the optional field's value is `Nothing` then the resulting object will not contain that field.

-}
maybeField : String -> (a -> Maybe f) -> Codec f -> ObjectCodec a (Maybe f -> b) -> ObjectCodec a b
maybeField name getter codec (ObjectCodec ocodec) =
    ObjectCodec
        { encoder =
            JE.optional name getter (encoder codec)
                :: ocodec.encoder
        , decoder =
            decoder codec
                |> JD.field name
                |> JD.maybe
                |> JD.map2 (\f x -> f x) ocodec.decoder
        }


{-| Specify the name getter and `Codec` for a required field, whose value can be `null`.

If the field is not present in the input then _the decoding fails_.
If the field's value is `Nothing` then the resulting object will contain the field with a `null` value.

This is a shorthand for a field having a codec built using `Codec.maybe`.

-}
nullableField : String -> (a -> Maybe f) -> Codec f -> ObjectCodec a (Maybe f -> b) -> ObjectCodec a b
nullableField name getter codec ocodec =
    field name getter (maybe codec) ocodec


{-| Create a `Codec` from a fully specified `ObjectCodec`.
-}
buildObject : ObjectCodec a a -> Codec a
buildObject (ObjectCodec om) =
    Codec
        { encoder =
            om.encoder
                |> List.reverse
                |> JE.object
        , decoder = om.decoder
        }



-- CUSTOM


{-| A partially built `Codec` for a custom type.
-}
type CustomCodec match v
    = CustomCodec
        { match : JE.UnionBuilder match
        , decoder : List (Decoder v)
        }


{-| Starts building a `Codec` for a custom type.

You need to pass a pattern matching function, built like this:

    type Semaphore
        = Red Int String
        | Yellow Float
        | Green

    semaphoreCodec : Codec Semaphore
    semaphoreCodec =
        Codec.custom
            (\red yellow green value ->
                case value of
                    Red i s ->
                        red i s

                    Yellow f ->
                        yellow f

                    Green ->
                        green
            )
            |> Codec.variant2 "Red" Red Codec.int Codec.string
            |> Codec.variant1 "Yellow" Yellow Codec.float
            |> Codec.variant0 "Green" Green
            |> Codec.buildCustom

-}
custom : match -> CustomCodec match value
custom match =
    CustomCodec
        { match = JE.union match
        , decoder = []
        }


variant :
    Codec input
    -> CustomCodec ((input -> JE.UnionEncodeValue) -> match) v
    -> CustomCodec match v
variant codec_ (CustomCodec am) =
    CustomCodec
        { match =
            am.match
                |> JE.variant (encoder codec_)
        , decoder = am.decoder
        }


{-| Define a variant with 0 parameters for a custom type.
-}
variant0 :
    String
    -> decodesTo
    -> CustomCodec (JE.UnionEncodeValue -> input) decodesTo
    -> CustomCodec input decodesTo
variant0 name ctor (CustomCodec am) =
    CustomCodec
        { match =
            am.match
                |> JE.variant0 name
        , decoder =
            JD.field "tag" (JD.literal ctor (Json.Encode.string name))
                :: am.decoder
        }


{-| Define a variant with 0 parameters for a custom type.
-}
variant1 :
    String
    -> (input -> decodesTo)
    -> Codec input
    ->
        CustomCodec
            ((input
              -> JE.UnionEncodeValue
             )
             -> decodesTo
             -> JE.UnionEncodeValue
            )
            decodesTo
    -> CustomCodec (decodesTo -> JE.UnionEncodeValue) decodesTo
variant1 name ctor codec (CustomCodec am) =
    let
        variantDecoder : JD.Decoder decodesTo
        variantDecoder =
            JD.map2 (\() -> ctor)
                (JD.field "tag"
                    (JD.literal () (Json.Encode.string name))
                )
                (decoder codec |> JD.field "args")

        encoderThing : JE.UnionBuilder (decodesTo -> JE.UnionEncodeValue)
        encoderThing =
            am.match
                |> JE.variant
                    (JE.object
                        [ JE.required "tag" (\_ -> name) (JE.literal (Json.Encode.string name))
                        , JE.required "args" identity (encoder codec)
                        ]
                    )
    in
    CustomCodec
        { match = encoderThing
        , decoder = variantDecoder :: am.decoder
        }


{-| Define a variant with 2 parameters for a custom type.
-}
variant2 :
    String
    -> (a -> b -> v)
    -> Codec a
    -> Codec b
    -> CustomCodec ((a -> b -> JE.UnionEncodeValue) -> c) v
    -> CustomCodec c v
variant2 name ctor m1 m2 (CustomCodec am) =
    let
        decoderOnly : Json.Decode.Decoder v
        decoderOnly =
            Json.Decode.map3 (\() -> ctor)
                (Json.Decode.field "tag"
                    (Json.Decode.string
                        |> Json.Decode.andThen
                            (\dV ->
                                if name == dV then
                                    Json.Decode.succeed ()

                                else
                                    Json.Decode.fail ("Expected the following tag: " ++ name)
                            )
                    )
                )
                (Json.Decode.field "args" (decoder m1 |> JD.decoder |> Json.Decode.index 0))
                (Json.Decode.field "args" (decoder m2 |> JD.decoder |> Json.Decode.index 1))

        nextThingy2 : (List Value -> Value) -> (a -> b -> JE.UnionEncodeValue)
        nextThingy2 listThing =
            let
                foo1 : Encoder a
                foo1 =
                    encoder m1

                foo2 : Encoder b
                foo2 =
                    encoder m2
            in
            \a b ->
                [ a |> JE.encoder foo1
                , b |> JE.encoder foo2
                ]
                    |> listThing
                    |> JE.UnionEncodeValue
    in
    variant_ name
        [ m1 |> encoder |> JE.tsType
        , m2 |> encoder |> JE.tsType
        ]
        nextThingy2
        decoderOnly
        (CustomCodec am)


variant_ :
    String
    -> List TsType
    -> ((List Value -> Value) -> a)
    -> Json.Decode.Decoder v
    -> CustomCodec (a -> b) v
    -> CustomCodec b v
variant_ name argTypes matchPiece decoderPiece (CustomCodec am) =
    let
        thing =
            JE.object
                [ --( "tag", JE.string name )
                  JE.required "tag" identity (JE.literal (Json.Encode.string name))
                , JE.required "args" identity (JE.list JE.value)

                --, JE.required "args" Tuple.pair JE.tuple
                ]

        enc =
            thing |> JE.encoder

        thisType =
            TsType.TypeObject
                [ ( TsType.Required, "tag", TsType.Literal (Json.Encode.string name) )
                , ( TsType.Required, "args", TsType.Tuple argTypes Nothing )
                ]
    in
    CustomCodec
        { match =
            case am.match of
                JE.UnionBuilder matcher types ->
                    JE.UnionBuilder (matcher (matchPiece enc))
                        --JE.tsType thing
                        (thisType :: types)

        --, decoder = Dict.insert name decoderPiece am.decoder
        , decoder =
            JD.Decoder decoderPiece thisType
                :: am.decoder
        }



--variant name
--    (\c v1 v2 ->
--        c
--            [ encoder m1 v1
--            , encoder m2 v2
--            ]
--    )
--    (JD.map2 ctor
--        (JD.index 0 <| decoder m1)
--        (JD.index 1 <| decoder m2)
--    )
--{-| Define a variant with 2 parameters for a custom type.
---}
--variant2 :
--    String
--    -> (a -> b -> v)
--    -> Codec a
--    -> Codec b
--    -> CustomCodec ((a -> b -> Value) -> c) v
--    -> CustomCodec c v
--variant2 name ctor m1 m2 =
--    variant name
--        (\c v1 v2 ->
--            c
--                [ encoder m1 v1
--                , encoder m2 v2
--                ]
--        )
--        (JD.map2 ctor
--            (JD.index 0 <| decoder m1)
--            (JD.index 1 <| decoder m2)
--        )
--
--
--{-| Define a variant with 3 parameters for a custom type.
---}
--variant3 :
--    String
--    -> (a -> b -> c -> v)
--    -> Codec a
--    -> Codec b
--    -> Codec c
--    -> CustomCodec ((a -> b -> c -> Value) -> partial) v
--    -> CustomCodec partial v
--variant3 name ctor m1 m2 m3 =
--    variant name
--        (\c v1 v2 v3 ->
--            c
--                [ encoder m1 v1
--                , encoder m2 v2
--                , encoder m3 v3
--                ]
--        )
--        (JD.map3 ctor
--            (JD.index 0 <| decoder m1)
--            (JD.index 1 <| decoder m2)
--            (JD.index 2 <| decoder m3)
--        )
--
--
--{-| Define a variant with 4 parameters for a custom type.
---}
--variant4 :
--    String
--    -> (a -> b -> c -> d -> v)
--    -> Codec a
--    -> Codec b
--    -> Codec c
--    -> Codec d
--    -> CustomCodec ((a -> b -> c -> d -> Value) -> partial) v
--    -> CustomCodec partial v
--variant4 name ctor m1 m2 m3 m4 =
--    variant name
--        (\c v1 v2 v3 v4 ->
--            c
--                [ encoder m1 v1
--                , encoder m2 v2
--                , encoder m3 v3
--                , encoder m4 v4
--                ]
--        )
--        (JD.map4 ctor
--            (JD.index 0 <| decoder m1)
--            (JD.index 1 <| decoder m2)
--            (JD.index 2 <| decoder m3)
--            (JD.index 3 <| decoder m4)
--        )
--
--
--{-| Define a variant with 5 parameters for a custom type.
---}
--variant5 :
--    String
--    -> (a -> b -> c -> d -> e -> v)
--    -> Codec a
--    -> Codec b
--    -> Codec c
--    -> Codec d
--    -> Codec e
--    -> CustomCodec ((a -> b -> c -> d -> e -> Value) -> partial) v
--    -> CustomCodec partial v
--variant5 name ctor m1 m2 m3 m4 m5 =
--    variant name
--        (\c v1 v2 v3 v4 v5 ->
--            c
--                [ encoder m1 v1
--                , encoder m2 v2
--                , encoder m3 v3
--                , encoder m4 v4
--                , encoder m5 v5
--                ]
--        )
--        (JD.map5 ctor
--            (JD.index 0 <| decoder m1)
--            (JD.index 1 <| decoder m2)
--            (JD.index 2 <| decoder m3)
--            (JD.index 3 <| decoder m4)
--            (JD.index 4 <| decoder m5)
--        )
--
--
--{-| Define a variant with 6 parameters for a custom type.
---}
--variant6 :
--    String
--    -> (a -> b -> c -> d -> e -> f -> v)
--    -> Codec a
--    -> Codec b
--    -> Codec c
--    -> Codec d
--    -> Codec e
--    -> Codec f
--    -> CustomCodec ((a -> b -> c -> d -> e -> f -> Value) -> partial) v
--    -> CustomCodec partial v
--variant6 name ctor m1 m2 m3 m4 m5 m6 =
--    variant name
--        (\c v1 v2 v3 v4 v5 v6 ->
--            c
--                [ encoder m1 v1
--                , encoder m2 v2
--                , encoder m3 v3
--                , encoder m4 v4
--                , encoder m5 v5
--                , encoder m6 v6
--                ]
--        )
--        (JD.map6 ctor
--            (JD.index 0 <| decoder m1)
--            (JD.index 1 <| decoder m2)
--            (JD.index 2 <| decoder m3)
--            (JD.index 3 <| decoder m4)
--            (JD.index 4 <| decoder m5)
--            (JD.index 5 <| decoder m6)
--        )
--
--
--{-| Define a variant with 7 parameters for a custom type.
---}
--variant7 :
--    String
--    -> (a -> b -> c -> d -> e -> f -> g -> v)
--    -> Codec a
--    -> Codec b
--    -> Codec c
--    -> Codec d
--    -> Codec e
--    -> Codec f
--    -> Codec g
--    -> CustomCodec ((a -> b -> c -> d -> e -> f -> g -> Value) -> partial) v
--    -> CustomCodec partial v
--variant7 name ctor m1 m2 m3 m4 m5 m6 m7 =
--    variant name
--        (\c v1 v2 v3 v4 v5 v6 v7 ->
--            c
--                [ encoder m1 v1
--                , encoder m2 v2
--                , encoder m3 v3
--                , encoder m4 v4
--                , encoder m5 v5
--                , encoder m6 v6
--                , encoder m7 v7
--                ]
--        )
--        (JD.map7 ctor
--            (JD.index 0 <| decoder m1)
--            (JD.index 1 <| decoder m2)
--            (JD.index 2 <| decoder m3)
--            (JD.index 3 <| decoder m4)
--            (JD.index 4 <| decoder m5)
--            (JD.index 5 <| decoder m6)
--            (JD.index 6 <| decoder m7)
--        )
--
--
--{-| Define a variant with 8 parameters for a custom type.
---}
--variant8 :
--    String
--    -> (a -> b -> c -> d -> e -> f -> g -> h -> v)
--    -> Codec a
--    -> Codec b
--    -> Codec c
--    -> Codec d
--    -> Codec e
--    -> Codec f
--    -> Codec g
--    -> Codec h
--    -> CustomCodec ((a -> b -> c -> d -> e -> f -> g -> h -> Value) -> partial) v
--    -> CustomCodec partial v
--variant8 name ctor m1 m2 m3 m4 m5 m6 m7 m8 =
--    variant name
--        (\c v1 v2 v3 v4 v5 v6 v7 v8 ->
--            c
--                [ encoder m1 v1
--                , encoder m2 v2
--                , encoder m3 v3
--                , encoder m4 v4
--                , encoder m5 v5
--                , encoder m6 v6
--                , encoder m7 v7
--                , encoder m8 v8
--                ]
--        )
--        (JD.map8 ctor
--            (JD.index 0 <| decoder m1)
--            (JD.index 1 <| decoder m2)
--            (JD.index 2 <| decoder m3)
--            (JD.index 3 <| decoder m4)
--            (JD.index 4 <| decoder m5)
--            (JD.index 5 <| decoder m6)
--            (JD.index 6 <| decoder m7)
--            (JD.index 7 <| decoder m8)
--        )
--
--


{-| Build a `Codec` for a fully specified custom type.
-}
buildCustom : CustomCodec (a -> JE.UnionEncodeValue) a -> Codec a
buildCustom (CustomCodec am) =
    Codec
        { encoder = am.match |> JE.buildUnion
        , decoder = JD.oneOf am.decoder
        }



-- INCONSISTENT STRUCTURE


{-| Try a set of decoders (in order).
The first argument is used for encoding and decoding, the list of other codecs is used as a fallback while decoding.

This is particularly useful for backwards compatibility. You would pass the current codec as the first argument,
and the old ones (eventually `map`ped) as a fallback list to use while decoding.

-}
oneOf : Codec a -> List (Codec a) -> Codec a
oneOf main alts =
    Codec
        { encoder = encoder main
        , decoder = JD.oneOf <| decoder main :: List.map decoder alts
        }



-- MAPPING


{-| Transform a `Codec`.
-}
map : (a -> b) -> (b -> a) -> Codec a -> Codec b
map go back codec =
    Codec
        { decoder = JD.map go <| decoder codec
        , encoder = encoder codec |> JE.map back
        }



-- FANCY


{-| Ignore the JSON and make the decoder fail. This is handy when used with
`oneOf` or `andThen` where you want to give a custom error message in some
case. The encoder will produce `null`.
-}
fail : String -> Codec a
fail msg =
    Codec
        { decoder = JD.fail msg
        , encoder = JE.null
        }



--{-| Create codecs that depend on previous results.
---}
--andThen : (a -> Codec b) -> (b -> a) -> Codec a -> Codec b
--andThen dec enc c =
--    Codec
--        { decoder = decoder c |> JD.andThen (dec >> decoder)
--        , encoder = encoder c << enc
--        }
--{-| Create a `Codec` for a recursive data structure.
--The argument to the function you need to pass is the fully formed `Codec`.
---}
--recursive : (Codec a -> Codec a) -> Codec a
--recursive f =
--    f <| lazy (\_ -> recursive f)


{-| Create a `Codec` that produces null as JSON and always decodes as the same value.
-}
succeed : a -> Codec a
succeed default_ =
    Codec
        { decoder = JD.succeed default_
        , encoder = JE.null
        }



--{-| This is useful for recursive structures that are not easily modeled with `recursive`.
--Have a look at the Json.Decode docs for examples.
---}
--lazy : (() -> Codec a) -> Codec a
--lazy f =
--    Codec
--        { decoder = JD.lazy (\_ -> decoder <| f ())
--        , encoder = \v -> encoder (f ()) v
--        }


{-| Create a `Codec` that doesn't transform the JSON value, just brings it to and from Elm as a `Value`.
-}
value : Codec Value
value =
    Codec
        { encoder = JE.value
        , decoder = JD.value
        }


{-| -}
tsType : Codec value -> TsType
tsType (Codec thing) =
    JD.tsType thing.decoder
