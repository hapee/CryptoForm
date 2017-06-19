module Main exposing (main)

{-| This is an obligatory comment

# Basics
@docs main
-}

import CryptoForm.Identities as Identities exposing (Identity, Msg(Select), selected)
import CryptoForm.Mailman as Mailman
import CryptoForm.Fields as Fields

import ElmMime.Main as Mime
import ElmMime.Attachments as Attachments exposing (Attachment, Msg(FileSelect, FileRemove), onChange)

import ElmPGP.Ports exposing (encrypt, ciphertext)

import Html exposing (Html, a, button, code, div, fieldset, form, hr, input, label, li, p, section, span, strong, text, ul)
import Html.Attributes exposing (attribute, class, disabled, href, novalidate, placeholder, style, type_, value)
import Html.Events exposing (onClick, onSubmit)



type alias Model =
  { base_url: String
  , identities: Identities.Model
  , name: String
  , email: String
  , subject: String
  , body: String
  , attachments: Attachments.Model
  }


type Msg
  = UpdateIdentities Identities.Msg
  | UpdateAttachments Attachments.Msg
  | UpdateName String
  | UpdateEmail String
  | UpdateSubject String
  | UpdateBody String
  | Stage
  | Send String
  | Mailman Mailman.Msg
  | Reset


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
  case msg of
    UpdateIdentities a ->
      let
        ( identities, cmd ) = Identities.update a model.identities
      in
        ( { model | identities = identities }, Cmd.map UpdateIdentities cmd )

    UpdateAttachments a ->
      let
        (attachments, cmd ) = Attachments.update a model.attachments
      in
        ( { model | attachments = attachments}, Cmd.map UpdateAttachments cmd )

    UpdateName name ->
        ( { model | name = name }, Cmd.none )

    UpdateEmail email ->
        ( { model | email = email }, Cmd.none )

    UpdateSubject subject ->
        ( { model | subject = subject }, Cmd.none )

    UpdateBody body ->
        ( { model | body = body }, Cmd.none )

    Stage ->
      let
        cmd = case (selected model.identities) of
          Just identity ->
            let
              -- Much of this needs to be configured with env-vars
              recipient = String.concat
                [ Identities.description identity
                , " <"
                , Identities.fingerprint identity
                , "@451labs.org>"
                ]
              headers =
                [ ("From", "CryptoForm <noreply@451labs.org>")
                , ("To", recipient)
                , ("Message-ID", "Placeholder-message-ID")
                , ("Subject", model.subject)
                ]
              parts =
                Mime.plaintext model.body ::
                (List.map Attachments.mime model.attachments)
              body = Mime.serialize headers parts
            in
              encrypt
                { data = body
                , publicKeys = Identities.publicKey identity
                , privateKeys = ""
                , armor = True
                }

          Nothing ->
            Cmd.none
      in
        ( model, cmd )

    Send ciphertext ->
      let
        payload = [ ("content", ciphertext) ]
        cmd = case (selected model.identities) of
          Just identity ->
            -- Can I send my ciphertext as a form upload instead?
            Mailman.send identity payload model.base_url
          Nothing ->
            Cmd.none
      in
        ( model, Cmd.map Mailman cmd )

    Mailman a ->
      let
        cmd = Mailman.update a
      in
        ( model, Cmd.map Mailman cmd )

    Reset ->
      ( reset model, Cmd.none )


-- VIEW functions
view : Model -> Html Msg
view model =
  form [ onSubmit Stage, novalidate True ]
    [ sectionView "Tell us about yourself" []
      [ fieldset []
        [ Fields.input "Name" "Your name" model.name UpdateName
        , Fields.input "From" "Your e-mail address" model.email UpdateEmail
        ]
      ]
    , sectionView "Compose your email" []
      [ fieldset []
        [ identitiesView model.identities
        , verifierView model.identities
        ]
      , fieldset []
        [ Fields.input "Subject" "E-mail subject" model.subject UpdateSubject
        , Fields.textarea model.body UpdateBody
        ]
      ]
      -- Handling attachments (might be refactored)
    , sectionView "Attachments" []
      [ Html.map UpdateAttachments (fieldset [] (attachmentsView (List.reverse model.attachments)))
      ]
    , sectionView "" [ class "btn-toolbar" ]
      [ button [ class "btn btn-lg btn-primary", type_ "Submit", disabled (not (ready model)) ] [ text "Send" ]
      , button [ class "btn btn-lg btn-danger", type_ "Reset", onClick Reset ] [ text "Reset" ]
      ]
    ]


sectionView : String -> List (Html.Attribute Msg) -> List (Html Msg) -> Html Msg
sectionView title attr dom =
  section attr (
    [ hr [] []
    , p [] [ strong [] [ text title ] ]
    ] ++ dom )


identitiesView : Identities.Model -> Html Msg
identitiesView model =
  let
    description = case (selected model) of
      Just identity ->
        Identities.description identity
      Nothing ->
        ""
  in
    div [ class "form-group"]
      [ div [ class "input-group" ]
        [ div [ class "input-group-btn" ]
          [ button [ type_ "button", class "btn btn-default btn-primary dropdown-toggle", disabled (not <| Identities.ready model), attribute "data-toggle" "dropdown", style [ ("min-width", "75px"), ("text-align", "right") ] ]
            [ text "To "
            , span [ class "caret" ] []
            ]
          , ul [ class "dropdown-menu" ]
            (List.map (\identity -> li [] [ a [ href "#", onClick <| UpdateIdentities (Select identity) ] [ text (Identities.description identity) ] ] ) (Identities.identities model))
          ]
        , input [ type_ "text", class "form-control", value description, disabled True, placeholder "Select your addressee..." ] [ ]
        ]
      ]


verifierView : Identities.Model -> Html Msg
verifierView model =
  let
    verifier = Identities.verifier model
    view = \cls fingerprint expl ->
      div [ class cls ]
        [ strong [] [ text "Fingerprint " ]
        , code [] [ text ( Identities.friendly fingerprint ) ]
        , p [] [ text expl ]
        ]
  in
    case verifier of
      Just ( fingerprint, True ) ->
        view "alert alert-success" fingerprint """
To ensure only the intended recipient can read you e-mail, check with him/her if
this is the correct key fingerprint. Some people mention their fingerprint on
business cards or in e-mail signatures. The fingerprint listed here matches the
one reported for this recipient by the server."""

      Just ( fingerprint, False ) ->
        view "alert alert-danger" fingerprint """
This fingerprint does not match the one reported for this recipient by the
server. To ensure only the intended recipient can read you e-mail, check with
him/her if this is the correct key fingerprint. Some people mention their
fingerprint on business cards or in e-mail signatures."""

      Nothing ->
        div [ class "alert hidden" ] []

attachmentView : Attachment -> Html Attachments.Msg
attachmentView attachment =
  let
    desc = String.concat([Attachments.filename attachment, " (", Attachments.mimeType attachment,  ")"])
  in
    div [ class "form-group" ]
    [ div [ class "input-group" ]
      [ div [ class "input-group-btn" ]
        [ button [ class "btn btn-default btn-danger", onClick (FileRemove attachment), style [ ("min-width", "75px"), ("text-align", "right") ] ]
          [ text "Delete"
          ]
        ]
      , input [ type_ "text", class "form-control", disabled True, value desc ] [ ]
      ]
    ]


attachmentsView : List Attachment -> List (Html Attachments.Msg)
attachmentsView attachments =
  List.map (\a -> attachmentView a) attachments ++
    [ div [ class "form-group" ]
      [ div [ class "input-group" ]
        [ div [ class "input-group-btn" ]
          [ label [ class "btn btn-default btn-primary", style [ ("min-width", "75px"), ("text-align", "right") ] ]
            [ text "Add"
            , input [ type_ "file", style [("display", "none")], onChange FileSelect ] []
            ]
          ]
        , input [ type_ "text", class "form-control", disabled True, value "Browse to add an attachment" ] [ ]
        ]
      ]
    ]


-- HOUSEKEEPING
ready : Model -> Bool
ready model =
  Nothing /= (selected model.identities)
  && (String.length model.name) /= 0
  && (String.length model.email) /= 0
  && (String.length model.subject) /= 0
  && (String.length model.body) /= 0


init : String -> ( Model, Cmd Msg )
init base_url =
  let
    ( identities, identities_cmd ) = Identities.init base_url
    cmd = Cmd.map UpdateIdentities identities_cmd
  in
    ( { base_url = base_url
      , identities = identities
      , name = ""
      , email = ""
      , subject = ""
      , body = ""
      , attachments = []
      } , cmd )


reset : Model -> Model
reset model =
  { base_url = model.base_url
  , identities = Identities.reset model.identities
  , name = ""
  , email = ""
  , subject = ""
  , body = ""
  , attachments = []
  }


{-| main
-}
main : Program Never Model Msg
main =
  Html.program
    { init = init "http://localhost:4000/api/"
    , view = view
    , update = update
    , subscriptions = always (Sub.batch
      [ ElmPGP.Ports.ciphertext Send
      , Sub.map UpdateIdentities Identities.subscriptions
      ])
    }
