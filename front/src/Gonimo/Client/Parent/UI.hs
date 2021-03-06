{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE GADTs #-}
module Gonimo.Client.Parent.UI where

import           Control.Lens
import           Data.Foldable
import           Data.Monoid
import qualified Gonimo.Client.DeviceList         as DeviceList
import           Reflex.Dom.Core

import qualified Data.Map                         as Map
import qualified Data.Set                         as Set
import qualified Gonimo.Client.App.Types          as App
-- import           Gonimo.Client.Parent.Internal
import qualified Gonimo.Client.Auth               as Auth
import           Gonimo.Client.ConfirmationButton (mayAddConfirmation)
import qualified Gonimo.Client.Invite             as Invite
import qualified Gonimo.Client.NavBar             as NavBar
import qualified Gonimo.Client.Parent.Connections as C
import           Gonimo.Client.Reflex.Dom
import           Gonimo.Client.Server             (webSocket_recv)
import           Gonimo.Client.Util               (volumeMeter)
import           Gonimo.Client.WebRTC.Channel     (ReceivingState (..),
                                                   Channel, worstState)
import           Gonimo.Db.Entities        (DeviceId)
import           Gonimo.Client.Prelude
import qualified GHCJS.DOM.MediaStream          as MediaStream
import           Gonimo.Types                   (_Baby)


ui :: forall m t. (HasWebView m, MonadWidget t m)
            => App.Config t -> App.Loaded t -> DeviceList.DeviceList t -> m (App.Screen t)
ui appConfig loaded deviceList = mdo
  connections' <- C.connections $ C.Config { C._configResponse = appConfig^.App.server.webSocket_recv
                                           , C._configAuthData = loaded^.App.authData
                                           , C._configConnectBaby = devicesUI^.DeviceList.uiConnect
                                           , C._configDisconnectAll = leftmost [ navBar^.NavBar.backClicked
                                                                               , navBar^.NavBar.homeClicked
                                                                               , viewUI^.C.videoViewNavBar^.NavBar.homeClicked
                                                                               , viewUI^.C.videoViewDisconnectAll
                                                                               ]
                                           , C._configDisconnectBaby = leftmost [ devicesUI^.DeviceList.uiDisconnect
                                                                                , viewUI^.C.videoViewDisconnectBaby
                                                                                ]
                                           }
  handleUnreliableAlert connections'

  let noStreamsLeft = fmap (const ()) . ffilter id $ Map.null <$> updated (connections'^.C.streams)

  let showParentView = const "isParentView" <$> leftmost [ devicesUI^.DeviceList.uiConnect
                                                         , devicesUI^.DeviceList.uiShowStream
                                                         ]
  let showParentManage = const "isParentManage" <$> leftmost [ viewUI^.C.videoViewNavBar^.NavBar.backClicked
                                                             , invite^.Invite.uiGoBack
                                                             , invite^.Invite.uiDone
                                                             , noStreamsLeft
                                                             ]
  let showInviteView = const "isInviteView" <$> inviteRequested

  selectedView <- holdDyn "isParentManage" $ leftmost [showParentView, showParentManage, showInviteView]

  (navBar, devicesUI, inviteRequested) <-
    elDynClass "div" (pure "container has-footer parentManage " <> selectedView) $ do
      manageUi appConfig loaded deviceList connections'

  viewUI <-
    elDynClass "div" (pure "container parentView " <> selectedView) $ do
      viewUi appConfig loaded deviceList connections'

  invite <-
    elDynClass "div" (pure "container inviteView " <> selectedView) $ do
      firstCreation <- headE inviteRequested
      let inviteUI
            = Invite.ui loaded
              $ Invite.Config { Invite._configResponse = appConfig^.App.server.webSocket_recv
                              , Invite._configSelectedFamily = loaded^.App.selectedFamily
                              , Invite._configAuthenticated = appConfig^.App.auth.Auth.authenticated
                              , Invite._configCreateInvitation = never
                              }
      dynInvite <- widgetHold (pure def) $ const inviteUI <$> firstCreation
      pure $ Invite.inviteSwitchPromptlyDyn dynInvite

  emptySubs <- holdDyn mempty never
  let parentApp = App.App { App._subscriptions = emptySubs
                          , App._request = connections'^.C.request
                                           <> devicesUI^.DeviceList.uiRequest
                                           <> invite^.Invite.request
                                           <> navBar^.NavBar.request
                                           <> viewUI^.C.videoViewNavBar.NavBar.request
                          }
  pure $ App.Screen { App._screenApp = parentApp
                    , App._screenGoHome = leftmost [ navBar^.NavBar.backClicked
                                                   , navBar^.NavBar.homeClicked
                                                   , viewUI^.C.videoViewNavBar^.NavBar.homeClicked
                                                   ]
                    }

manageUi :: forall m t. (HasWebView m, MonadWidget t m)
            => App.Config t -> App.Loaded t -> DeviceList.DeviceList t -> C.Connections t -> m (NavBar.NavBar t, DeviceList.UI t, Event t ())
manageUi _ loaded deviceList connections' = do
      navBar <- NavBar.navBar (NavBar.Config loaded deviceList)
      let openStreams = connections'^.C.streams
      navBar' <- NavBar.NavBar
                 <$> mayAddConfirmation leaveConfirmation (navBar^.NavBar.backClicked) (not . Map.null <$> openStreams)
                 <*> mayAddConfirmation leaveConfirmation (navBar^.NavBar.homeClicked) (not . Map.null <$> openStreams)
                 <*> pure (navBar^.NavBar.request)

      devicesUI <- DeviceList.ui loaded deviceList
                   (fmap worstState <$> connections'^.C.channelMap)
                   (Set.fromList . Map.keys <$> openStreams)
      inviteRequested <- elClass "div" "footer" $
            makeClickable . elAttr' "div" (addBtnAttrs "device-add") $ text " ADD DEVICE"

      pure (navBar', devicesUI, inviteRequested)

viewUi :: forall m t. (HasWebView m, MonadWidget t m)
            => App.Config t -> App.Loaded t -> DeviceList.DeviceList t -> C.Connections t -> m (C.VideoView t)
viewUi _ loaded deviceList connections = do
  let streams = connections^.C.streams
  let singleVideoClass = (\streams' -> if Map.size streams' == 1 then "single-video " else "") <$> streams
  elDynClass "div" (pure "parent " <> singleVideoClass) $ do
    navBar <- NavBar.navBar (NavBar.Config loaded deviceList)

    navBar' <- NavBar.NavBar (navBar^.NavBar.backClicked)
              <$> mayAddConfirmation leaveConfirmation (navBar^.NavBar.homeClicked) (not . null <$> streams)
              <*> pure (navBar^.NavBar.request)

    _ <- dyn $ renderFakeVideos connections
    closedsEvEv <- dyn $ renderVideos deviceList connections
    let closedEvEv  = leftmost <$> closedsEvEv
    closedEv <- switchPromptly never closedEvEv
    stopAllClicked <- elClass "div" "stream-menu" $
        makeClickable . elAttr' "div" (addBtnAttrs "stop") $ text "STOP ALL"
    pure $ C.VideoView navBar' closedEv stopAllClicked

renderFakeVideos :: forall m t. (HasWebView m, MonadWidget t m) => C.Connections t -> Dynamic t (m ())
renderFakeVideos connections =
  let
    renderFake stream = mediaVideo stream ("autoplay" =: "true" <> "style" =: "width:100%;height:100%;" <> "class" =: "fakeVideo" <> "muted" =: "true")
  in
    traverse_ renderFake . Map.elems <$> connections^.C.origStreams

renderVideos :: forall m t. (HasWebView m, MonadWidget t m) => DeviceList.DeviceList t -> C.Connections t -> Dynamic t (m [Event t DeviceId])
renderVideos deviceList connections' = traverse renderVideo . Map.toList <$> connections'^.C.streams
  where
    dynChannelMap = connections'^.C.channelMap

    renderVideo :: (DeviceId, C.StreamData t) -> m (Event t DeviceId)
    renderVideo (key, C.StreamData stream volEvent) = do
      hasVideo <- not . null <$> MediaStream.getVideoTracks stream
      let hasBackground = if hasVideo then "" else "justAudio "
      elDynClass "div" (dynConnectionClass key <> pure "stream-baby " <> pure hasBackground) $ do
        elClass "div" "broken-overlay" $ do
          elClass "div" "broken-message" $ text "Connection Lost!"
        elClass "div" "stream-baby-heading" $ do
          elClass "div" "stream-baby-name" $ do
            el "h1" $ dynText ((^. at key._Just._Baby) <$> deviceList^.DeviceList.onlineDevices)
        mediaVideo stream ("autoplay" =: "true")
        closeClicked <- makeClickable $ elAttr' "div" (addBtnAttrs "btn-close-x") blank
        if True
          then renderVolumemeter volEvent
          else volumeMeter stream
        pure $ const key <$> closeClicked

    dynConnectionClass key = connectionClass key <$> dynChannelMap

    connectionClass :: DeviceId -> Map.Map DeviceId (Channel t) -> Text
    connectionClass key chanMap = case chanMap ^? at key . _Just . to worstState of
                               Just StateUnreliable -> "connectionUnreliable "
                               Just StateBroken -> "connectionBroken "
                               -- Just StateReceiving -> "connectionReliable "
                               _ -> ""

    -- isUnreliable Nothing = False
    -- isUnreliable (Just chan) = chan^.audioReceivingState == StateUnreliable
    --                            || chan^.videoReceivingState == StateUnreliable


leaveConfirmation :: DomBuilder t m => m ()
leaveConfirmation = do
    el "h3" $ text "Really stop parent station?"
    el "p" $ text "All open streams will be disconnected!"

handleUnreliableAlert :: forall t m. MonadWidget t m => C.Connections t -> m ()
handleUnreliableAlert connections' = mdo
  let gotUnreliable = updated $ connections'^.C.unreliableConnections

  let
    renderAlert False = dismissibleOverlay "success-overlay " 4 $ text "Connection is reliable!"
    renderAlert True = dismissibleOverlay "warning-overlay " 6 $ do
      text "Connection unreliable!"
      el "br" blank
      text "Might break unnoticed (no alert)!"
  _ <- widgetHold (pure ()) $ renderAlert <$> gotUnreliable
  pure ()

-- Old currently no longer used:
unreliableAlert :: forall t m. MonadWidget t m => m (Event t ())
unreliableAlert = do
  elClass "div" "fullScreenOverlay" $ do
    elClass "div" "container" $ do
      el "h1" $ text "Connection probably unreliable!"
      el "br" blank
      el "br" blank
      text "We are sorry, we can not guarantee a reliable connection to your child on this browser!"
      el "br" blank
      text "This is indicated by a red border around the connected device and the video, if you don't see a red border this was a false alert - sorry about that."
      el "br" blank
      text "If you see a red border, this means the connection might break unnoticed at any time - there will be no alarm!"
      el "br" blank
      el "h1" $ text "What can I do?"
      el "ul" $ do
        el "li" $ text "Use a different browser - currently we recommend Chrome."
        el "li" $ text "Disconnect/Connect periodically to be sure everything is alright."
        el "li" $ text "For Audio connections, have some sound at the baby side, e.g. open the window."
        el "li" $ text "For Video connections, have some constant motion in the picture, for example a clock."

      el "br" blank
      el "br" blank

      okClicked <- makeClickable . elAttr' "div" (addBtnAttrs "btn-lang") $ text "OK"
      pure $ okClicked
