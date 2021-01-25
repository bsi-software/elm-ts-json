module TsInterop.Encode exposing
    ( Encoder
    , string, int, float, literal, bool, null
    , map
    , object, Property, optional, required
    , UnionBuilder, union, variant, variant0, variantObject, variantLiteral, buildUnion
    , UnionEncodeValue
    , list, dict, tuple, triple, maybe
    , value
    , typeDef, encoder, tsType
    )

{-| The `TsInterop.Encode` module is what you use for

  - FromElm Ports

See [TsJson.Decode](TsJson.Decode) for the API used for Flags and ToElm Ports.

By building an `Encoder` with this API, you're also describing the source of truth for taking an Elm type and
turning it into a JSON value with a TypeScript type. Note that there is no magic involved in this process.
The `elm-ts-interop` CLI simply gets the [`typeDef`](#typeDef) from your `Encoder` to generate the
TypeScript Declaration file for your compiled Elm code.

@docs Encoder


## Built-Ins

@docs string, int, float, literal, bool, null


## Transforming

@docs map


## Objects

@docs object, Property, optional, required


## Union Types

    import Json.Encode as Encode

    runExample : Encoder input -> input -> { output : String, tsType : String }
    runExample encoder_ input =
        { tsType = typeDef encoder_, output = input |> encoder encoder_ |> Encode.encode 0 }

    type ToJs
        = SendPresenceHeartbeat
        | Alert String

    unionEncoder : Encoder ToJs
    unionEncoder =
        union
            (\vSendHeartbeat vAlert value ->
                case value of
                    SendPresenceHeartbeat ->
                        vSendHeartbeat
                    Alert string ->
                        vAlert string
            )
            |> variant0 "SendPresenceHeartbeat"
            |> variantObject "Alert" [ required "message" identity string ]
            |> buildUnion


    Alert "Hello TypeScript!"
            |> runExample unionEncoder
    --> { output = """{"tag":"Alert","message":"Hello TypeScript!"}"""
    --> , tsType = """{ tag : "Alert"; message : string } | { tag : "SendPresenceHeartbeat" }"""
    --> }

@docs UnionBuilder, union, variant, variant0, variantObject, variantLiteral, buildUnion

@docs UnionEncodeValue


## Collections

@docs list, dict, tuple, triple, maybe


## In-Depth Example

You can use `elm-ts-interop` to build up `Encoder`s that have the same TypeScript type as a web platform API expects.
Here's an example that we could use to call the [`scrollIntoView`](https://developer.mozilla.org/en-US/docs/Web/API/Element/scrollIntoView)
method on a DOM Element.

    import Json.Encode

    type Behavior
        = Auto
        | Smooth

    type Alignment
        = Start
        | Center
        | End
        | Nearest

    scrollIntoViewEncoder : Encoder
            { behavior : Maybe Behavior
            , block : Maybe Alignment
            , inline : Maybe Alignment
            }
    scrollIntoViewEncoder =
        object
            [ optional "behavior" .behavior behaviorEncoder
            , optional "block" .block alignmentEncoder
            , optional "inline" .inline alignmentEncoder
            ]

    behaviorEncoder : Encoder Behavior
    behaviorEncoder =
        union
            (\vAuto vSmooth value ->
                case value of
                    Auto ->
                        vAuto
                    Smooth ->
                        vSmooth
            )
            |> variantLiteral (Json.Encode.string "auto")
            |> variantLiteral (Json.Encode.string "smooth")
            |> buildUnion


    alignmentEncoder : Encoder Alignment
    alignmentEncoder =
        union
            (\vStart vCenter vEnd vNearest value ->
                case value of
                    Start ->
                        vStart
                    Center ->
                        vCenter
                    End ->
                        vEnd
                    Nearest ->
                        vNearest
            )
            |> variantLiteral (Json.Encode.string "start")
            |> variantLiteral (Json.Encode.string "center")
            |> variantLiteral (Json.Encode.string "end")
            |> variantLiteral (Json.Encode.string "nearest")
            |> buildUnion


    { behavior = Just Auto, block = Just Nearest, inline = Nothing }
            |> runExample scrollIntoViewEncoder
    --> { output = """{"behavior":"auto","block":"nearest"}"""
    --> , tsType = """{ behavior? : "smooth" | "auto"; block? : "nearest" | "end" | "center" | "start"; inline? : "nearest" | "end" | "center" | "start" }"""
    --> }


## Escape Hatch

@docs value


## Executing Encoders

Usually you don't need to use these functions directly, but instead the code generated by the `elm-ts-interop` command line
tool will use these for you under the hood. These can be helpful for debugging, or for building new tools on top of this package.

@docs typeDef, encoder, tsType

-}

import Dict exposing (Dict)
import Internal.TsJsonType exposing (..)
import Internal.TypeReducer as TypeReducer
import Internal.TypeToString as TypeToString
import Json.Encode as Encode


{-| Similar to a `Json.Encode.Value` in `elm/json`. However, a `TsInterop.Encode.Encoder` in `elm-ts-interop` has this key difference from an `elm/json` `Encode.Value`:

  - `elm/json` `Json.Encode.Value` - a value representing an encoded JSON value
  - `elm-ts-interop` `TsInterop.Encode.Encoder` - a _function_ for turning an Elm value into an encoded JSON value. The `Encoder` itself has a definite TypeScript type, before you even pass in an Elm value to turn into JSON.

So the `elm-ts-interop` `Encoder` expects a specific type of Elm value, and knows how to turn that Elm value into JSON.

Let's compare the two with an example for encoding a first and last name.

    import Json.Encode

    runExample : Encoder input -> input -> { output : String, tsType : String }
    runExample encoder_ input =
        { tsType = typeDef encoder_, output = input |> encoder encoder_ |> Json.Encode.encode 0 }

    elmJsonNameEncoder : { first : String, last : String }
        -> Json.Encode.Value
    elmJsonNameEncoder { first, last } =
        Json.Encode.object
            [ ( "first", Json.Encode.string first )
            , ( "last", Json.Encode.string last )
            ]

    { first = "James", last = "Kirk" }
            |> elmJsonNameEncoder
            |> Json.Encode.encode 0
    --> """{"first":"James","last":"Kirk"}"""

    nameEncoder : Encoder { first : String, last : String }
    nameEncoder =
        object
            [ required "first" .first string
            , required "last" .last string
            ]

    { first = "James", last = "Kirk" }
            |> runExample nameEncoder
    --> { output = """{"first":"James","last":"Kirk"}"""
    --> , tsType = "{ first : string; last : string }"
    --> }

-}
type Encoder input
    = Encoder (input -> Encode.Value) TsType


{-| -}
encoder : Encoder input -> (input -> Encode.Value)
encoder (Encoder encodeFn _) input =
    encodeFn input


{-| -}
typeDef : Encoder input -> String
typeDef (Encoder _ tsType_) =
    TypeToString.toString tsType_


{-| -}
tsType : Encoder input -> TsType
tsType (Encoder _ tsType_) =
    tsType_


{-| -}
type Property input
    = Property PropertyOptionality String (input -> Maybe Encode.Value) TsType


{-| -}
optional : String -> (input -> Maybe mappedInput) -> Encoder mappedInput -> Property input
optional name getter (Encoder encodeFn tsType_) =
    Property
        Optional
        name
        (\input -> input |> getter |> Maybe.map encodeFn)
        tsType_


{-| -}
required : String -> (input -> mappedInput) -> Encoder mappedInput -> Property input
required name getter (Encoder encodeFn tsType_) =
    Property
        Required
        name
        (\input -> input |> getter |> encodeFn |> Just)
        tsType_


{-|

    import Json.Encode as Encode

    runExample : Encoder input -> input -> { output : String, tsType : String }
    runExample encoder_ input =
        { tsType = typeDef encoder_, output = input |> encoder encoder_ |> Encode.encode 0 }

    nameEncoder : Encoder { first : String, last : String }
    nameEncoder =
        object
            [ required "first" .first string
            , required "last" .last string
            ]


    { first = "James", last = "Kirk" }
            |> runExample nameEncoder
    --> { output = """{"first":"James","last":"Kirk"}"""
    --> , tsType = "{ first : string; last : string }"
    --> }

    fullNameEncoder : Encoder { first : String, middle : Maybe String, last : String }
    fullNameEncoder =
        object
            [ required "first" .first string
            , optional "middle" .middle string
            , required "last" .last string
            ]

    { first = "James", middle = Just "Tiberius", last = "Kirk" }
            |> runExample fullNameEncoder
    --> { output = """{"first":"James","middle":"Tiberius","last":"Kirk"}"""
    --> , tsType = "{ first : string; middle? : string; last : string }"
    --> }

-}
object : List (Property input) -> Encoder input
object propertyEncoders =
    let
        propertyTypes : TsType
        propertyTypes =
            propertyEncoders
                |> List.map
                    (\(Property optionality propertyName _ tsType_) ->
                        ( optionality, propertyName, tsType_ )
                    )
                |> TypeObject

        encodeObject : input -> Encode.Value
        encodeObject input =
            propertyEncoders
                |> List.filterMap
                    (\(Property _ propertyName encodeFn _) ->
                        encodeFn input
                            |> Maybe.map
                                (\encoded ->
                                    ( propertyName, encoded )
                                )
                    )
                |> Encode.object
    in
    Encoder encodeObject propertyTypes


{-|

    import Json.Encode as Encode

    runExample : Encoder input -> input -> { output : String, tsType : String }
    runExample encoder_ input = { tsType = typeDef encoder_ , output = input |> encoder encoder_ |> Encode.encode 0 }


    True
        |> runExample bool
    --> { output = "true"
    --> , tsType = "boolean"
    --> }

-}
bool : Encoder Bool
bool =
    Encoder Encode.bool Boolean


{-|

    import Json.Encode as Encode

    runExample : Encoder input -> input -> { output : String, tsType : String }
    runExample encoder_ input = { tsType = typeDef encoder_ , output = input |> encoder encoder_ |> Encode.encode 0 }


    123
        |> runExample int
    --> { output = "123"
    --> , tsType = "number"
    --> }

-}
int : Encoder Int
int =
    Encoder Encode.int Integer


{-|

    import Json.Encode as Encode

    runExample : Encoder input -> input -> { output : String, tsType : String }
    runExample encoder_ input = { tsType = typeDef encoder_ , output = input |> encoder encoder_ |> Encode.encode 0 }


    123.45
        |> runExample float
    --> { output = "123.45"
    --> , tsType = "number"
    --> }

-}
float : Encoder Float
float =
    Encoder Encode.float Number


{-| Encode a string.

    import Json.Encode as Encode

    runExample : Encoder input -> input -> { output : String, tsType : String }
    runExample encoder_ input = { tsType = typeDef encoder_ , output = input |> encoder encoder_ |> Encode.encode 0 }


    "Hello!"
        |> runExample string
    --> { output = "\"Hello!\""
    --> , tsType = "string"
    --> }

You can use `map` to apply an accessor function for how to get that String.

    { data = { first = "James", last = "Kirk" } }
        |> runExample ( string |> map .first |> map .data )
    --> { output = "\"James\""
    --> , tsType = "string"
    --> }

-}
string : Encoder String
string =
    Encoder Encode.string String


{-| TypeScript has the concept of a [Literal Type](https://www.typescriptlang.org/docs/handbook/literal-types.html).
A Literal Type is just a JSON value. But unlike other types, it is constrained to a specific literal.

For example, `200` is a Literal Value (not just any `number`). Elm doesn't have the concept of Literal Values that the
compiler checks. But you can map Elm Custom Types nicely into TypeScript Literal Types. For example, you could represent
HTTP Status Codes in TypeScript with a Union of Literal Types like this:

```typescript
type HttpStatus = 200 | 404 // you can include more status codes
```

The type `HttpStatus` is limited to that set of numbers. In Elm, you might represent that discrete set of values with
a Custom Type, like so:

    type HttpStatus
        = Success
        | NotFound

However you name them, you can map those Elm types into equivalent TypeScript values using a union of literals like so:

    import Json.Encode as Encode

    runExample : Encoder input -> input -> { output : String, tsType : String }
    runExample encoder_ input = { tsType = typeDef encoder_ , output = input |> encoder encoder_ |> Encode.encode 0 }

    httpStatusEncoder : Encoder HttpStatus
    httpStatusEncoder =
        union
            (\vSuccess vNotFound value ->
                case value of
                    Success ->
                        vSuccess
                    NotFound ->
                        vNotFound
            )
            |> variantLiteral (Encode.int 200)
            |> variantLiteral (Encode.int 404)
            |> buildUnion

    NotFound
        |> runExample httpStatusEncoder
    --> { output = "404"
    --> , tsType = "404 | 200"
    --> }

-}
literal : Encode.Value -> Encoder a
literal literalValue =
    Encoder (\_ -> literalValue) (Literal literalValue)


{-| Equivalent to `literal Encode.null`.

    import Json.Encode as Encode

    runExample : Encoder input -> input -> { output : String, tsType : String }
    runExample encoder_ input = { tsType = typeDef encoder_ , output = input |> encoder encoder_ |> Encode.encode 0 }


    ()
        |> runExample null
    --> { output = "null"
    --> , tsType = "null"
    --> }

-}
null : Encoder input
null =
    literal Encode.null


{-| This is an escape hatch that allows you to send arbitrary JSON data. The type will
be JSON in TypeScript, so you won't have any specific type information. In some cases,
this is fine, but in general you'll usually want to use other functions in this module
to build up a well-typed [`Encoder`](#Encoder).
-}
value : Encoder Encode.Value
value =
    Encoder identity Unknown


{-| An [`Encoder`](#Encoder) represents turning an Elm input value into a JSON value that has a TypeScript type information.

This `map` function allows you to transform the **Elm input value**, not the resulting JSON output. So this will feel
different than using [`TsJson.Decode.map`](TsJson.Decode#map), or other familiar `map` functions
that transform an **Elm output value**, such as `Maybe.map` and `Json.Decode.map`.

Think of `TsInterop.Encode.map` as changing **how to get the value that you want to turn into JSON**. For example,
if we're passing in some nested data and need to get a field

    import Json.Encode as Encode

    runExample : input -> Encoder input -> { output : String, tsType : String }
    runExample input encoder_ = { tsType = typeDef encoder_ , output = input |> encoder encoder_ |> Encode.encode 0 }

    picardData : { data : { first : String, last : String, rank : String } }
    picardData = { data = { first = "Jean Luc", last = "Picard", rank = "Captain" } }


    string
        |> map .rank
        |> map .data
        |> runExample picardData
    --> { output = "\"Captain\""
    --> , tsType = "string"
    --> }

Let's consider how the types change as we `map` the `Encoder`.

    encoder1 : Encoder String
    encoder1 =
        string

    encoder2 : Encoder { rank : String }
    encoder2 =
        string
            |> map .rank

    encoder3 : Encoder { data : { rank : String } }
    encoder3 =
        string
            |> map .rank
            |> map .data

    (encoder1, encoder2, encoder3) |> always ()
    --> ()

So `map` is applying a function that tells the Encoder how to get the data it needs.

If we want to send a string through a port, then we start with a [`string`](#string) `Encoder`. Then we `map` it to
turn our input data into a String (because `string` is `Encoder String`).

    string
        |> map (\outerRecord -> outerRecord.data.first ++ " " ++ outerRecord.data.last)
        |> runExample picardData
    --> { output = "\"Jean Luc Picard\""
    --> , tsType = "string"
    --> }

-}
map : (input -> mappedInput) -> Encoder mappedInput -> Encoder input
map mapFunction (Encoder encodeFn tsType_) =
    Encoder (\input -> input |> mapFunction |> encodeFn) tsType_


{-|

    import Json.Encode as Encode

    runExample : Encoder input -> input -> { output : String, tsType : String }
    runExample encoder_ input = { tsType = typeDef encoder_ , output = input |> encoder encoder_ |> Encode.encode 0 }


    Just 42
        |> runExample ( maybe int )
    --> { output = "42"
    --> , tsType = "number | null"
    --> }

-}
maybe : Encoder a -> Encoder (Maybe a)
maybe encoder_ =
    union
        (\vNull vJust maybeValue ->
            case maybeValue of
                Just justValue ->
                    vJust justValue

                Nothing ->
                    vNull
        )
        |> variantLiteral Encode.null
        |> variant encoder_
        |> buildUnion


{-|

    import Json.Encode as Encode

    runExample : Encoder input -> input -> { output : String, tsType : String }
    runExample encoder_ input = { tsType = typeDef encoder_ , output = input |> encoder encoder_ |> Encode.encode 0 }


    [ "Hello", "World!" ]
        |> runExample ( list string )
    --> { output = """["Hello","World!"]"""
    --> , tsType = "string[]"
    --> }

-}
list : Encoder a -> Encoder (List a)
list (Encoder encodeFn tsType_) =
    Encoder
        (\input -> Encode.list encodeFn input)
        (List tsType_)


{-| TypeScript [has a Tuple type](https://www.typescriptlang.org/docs/handbook/basic-types.html#tuple). It's just an
Array with 2 items, and the TypeScript compiler will enforce that there are two elements. You can turn an Elm Tuple
into a TypeScript Tuple.

    import Json.Encode as Encode

    runExample : Encoder input -> input -> { output : String, tsType : String }
    runExample encoder_ input = { tsType = typeDef encoder_ , output = input |> encoder encoder_ |> Encode.encode 0 }


    ( "John Doe", True )
        |> runExample ( tuple string bool )
    --> { output = """["John Doe",true]"""
    --> , tsType = "[ string, boolean ]"
    --> }

If your target Elm value isn't a tuple, you can [`map`](#map) it into one

    { name = "John Smith", isAdmin = False }
        |> runExample
            (tuple string bool
                |> map
                    (\{ name, isAdmin } ->
                        ( name, isAdmin )
                    )
            )
    --> { output = """["John Smith",false]"""
    --> , tsType = "[ string, boolean ]"
    --> }

-}
tuple : Encoder input1 -> Encoder input2 -> Encoder ( input1, input2 )
tuple (Encoder encodeFn1 tsType1) (Encoder encodeFn2 tsType2) =
    Encoder
        (\( input1, input2 ) ->
            Encode.list identity [ encodeFn1 input1, encodeFn2 input2 ]
        )
        (Tuple [ tsType1, tsType2 ] Nothing)


{-| Same as [`tuple`](#tuple), but with Triples

    import Json.Encode as Encode

    runExample : Encoder input -> input -> { output : String, tsType : String }
    runExample encoder_ input = { tsType = typeDef encoder_ , output = input |> encoder encoder_ |> Encode.encode 0 }


    ( "Jane Doe", True, 123 )
        |> runExample ( triple string bool int )
    --> { output = """["Jane Doe",true,123]"""
    --> , tsType = "[ string, boolean, number ]"
    --> }

-}
triple : Encoder input1 -> Encoder input2 -> Encoder input3 -> Encoder ( input1, input2, input3 )
triple (Encoder encodeFn1 tsType1) (Encoder encodeFn2 tsType2) (Encoder encodeFn3 tsType3) =
    Encoder
        (\( input1, input2, input3 ) ->
            Encode.list identity
                [ encodeFn1 input1
                , encodeFn2 input2
                , encodeFn3 input3
                ]
        )
        (Tuple [ tsType1, tsType2, tsType3 ] Nothing)


{-|

    import Json.Encode as Encode
    import Dict

    runExample : Encoder input -> input -> { output : String, tsType : String }
    runExample encoder_ input = { tsType = typeDef encoder_ , output = input |> encoder encoder_ |> Encode.encode 0 }


    Dict.fromList [ ( "a", "123" ), ( "b", "456" ) ]
        |> runExample ( dict identity string )
    --> { output = """{"a":"123","b":"456"}"""
    --> , tsType = "{ [key: string]: string }"
    --> }

-}
dict : (comparableKey -> String) -> Encoder input -> Encoder (Dict comparableKey input)
dict keyToString (Encoder encodeFn tsType_) =
    Encoder
        (\input -> Encode.dict keyToString encodeFn input)
        (ObjectWithUniformValues tsType_)


{-| -}
union :
    constructor
    -> UnionBuilder constructor
union constructor =
    UnionBuilder constructor []


{-| -}
type UnionBuilder match
    = UnionBuilder match (List TsType)


{-| -}
variant0 :
    String
    -> UnionBuilder (UnionEncodeValue -> match)
    -> UnionBuilder match
variant0 variantName (UnionBuilder builder tsTypes_) =
    let
        thing : UnionBuilder ((() -> UnionEncodeValue) -> match)
        thing =
            UnionBuilder
                (builder
                    |> transformBuilder
                )
                tsTypes_

        transformBuilder : (UnionEncodeValue -> match) -> (() -> UnionEncodeValue) -> match
        transformBuilder matchBuilder encoderFn =
            matchBuilder (encoderFn ())
    in
    variant
        (object
            [ required "tag" identity (literal (Encode.string variantName)) ]
        )
        thing


{-| -}
variant :
    Encoder input
    -> UnionBuilder ((input -> UnionEncodeValue) -> match)
    -> UnionBuilder match
variant (Encoder encoder_ tsType_) (UnionBuilder builder tsTypes_) =
    UnionBuilder
        (builder (encoder_ >> UnionEncodeValue))
        (tsType_ :: tsTypes_)


{-| -}
variantLiteral :
    Encode.Value
    -> UnionBuilder (UnionEncodeValue -> match)
    -> UnionBuilder match
variantLiteral literalValue (UnionBuilder builder tsTypes) =
    UnionBuilder
        (builder (literalValue |> UnionEncodeValue))
        (Literal literalValue :: tsTypes)


{-| -}
variantObject :
    String
    -> List (Property arg1)
    -> UnionBuilder ((arg1 -> UnionEncodeValue) -> match)
    -> UnionBuilder match
variantObject variantName objectFields unionBuilder =
    variant
        (object
            (required "tag" identity (literal (Encode.string variantName))
                :: objectFields
            )
        )
        unionBuilder


{-| We can guarantee that you're only encoding to a given
set of possible shapes in a union type by ensuring that
all the encoded values come from the union pipeline,
using functions like `variantLiteral`, `variantObject`, etc.

Applying another variant function in your union pipeline will
give you more functions/values to give UnionEncodeValue's with
different shapes, if you need them.

-}
type UnionEncodeValue
    = UnionEncodeValue Encode.Value


unwrapUnion : UnionEncodeValue -> Encode.Value
unwrapUnion (UnionEncodeValue rawValue) =
    rawValue


{-| -}
buildUnion : UnionBuilder (match -> UnionEncodeValue) -> Encoder match
buildUnion (UnionBuilder toValue tsTypes_) =
    Encoder (toValue >> unwrapUnion) (TypeReducer.union tsTypes_)
