defmodule SpecterTest do
  use SpecterTest.Case
  doctest Specter

  @uuid_regex ~r/\b[0-9a-f]{8}\b-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-\b[0-9a-f]{12}\b/i

  describe "init" do
    test "initializes with default configuration" do
      assert {:ok, %Specter{native: ref}} = Specter.init()
      assert is_reference(ref)
    end

    test "initializes with ice_server configuration" do
      assert {:ok, %Specter{native: ref}} =
               Specter.init(ice_servers: ["stun:stun.example.com:3478"])

      assert is_reference(ref)
    end
  end

  describe "close_peer_connection" do
    setup [:initialize_specter, :init_api]

    test "returns {:error, :not_found} when given a random api id", %{specter: specter} do
      assert {:error, :not_found} = Specter.close_peer_connection(specter, UUID.uuid4())
    end

    test "returns :ok, then receives a closed message", %{specter: specter, api: api} do
      assert {:ok, pc} = Specter.new_peer_connection(specter, api)
      assert_receive {:peer_connection_ready, ^pc}

      assert :ok = Specter.close_peer_connection(specter, pc)
      assert_receive {:peer_connection_closed, ^pc}
    end
  end

  describe "config" do
    test "returns the current configuration" do
      assert {:ok, ref} =
               Specter.init(
                 ice_servers: [
                   "stun:stun.example.com:3478",
                   "stun:stun.l.example.com:3478"
                 ]
               )

      assert {:ok,
              %Specter.Config{
                ice_servers: [
                  "stun:stun.example.com:3478",
                  "stun:stun.l.example.com:3478"
                ]
              }} = Specter.config(ref)
    end
  end

  describe "add_ice_candidate" do
    setup [:initialize_specter, :init_api, :init_peer_connection]

    test "returns {:error, :not_found} when given a random api id", %{specter: specter} do
      assert {:error, :not_found} = Specter.add_ice_candidate(specter, UUID.uuid4(), "")
    end

    test "sends error messages back to Elixir", %{specter: specter, peer_connection: pc_offer} do
      api = init_api(specter)
      pc_answer = init_peer_connection(specter, api)

      assert :ok = Specter.create_data_channel(specter, pc_offer, "foo")
      assert :ok = Specter.create_offer(specter, pc_offer)
      assert_receive {:offer, ^pc_offer, offer}
      assert :ok = Specter.set_local_description(specter, pc_offer, offer)

      assert_receive {:ice_candidate, ^pc_offer, candidate}

      assert :ok = Specter.add_ice_candidate(specter, pc_answer, candidate)
      assert_receive {:candidate_error, ^pc_answer, "remote description is not set"}
    end

    test "adds the candidate to a peer connection", %{specter: specter, peer_connection: pc_offer} do
      api = init_api(specter)
      pc_answer = init_peer_connection(specter, api)

      assert :ok = Specter.create_data_channel(specter, pc_offer, "foo")
      assert_receive {:data_channel_created, ^pc_offer}
      assert :ok = Specter.create_offer(specter, pc_offer)
      assert_receive {:offer, ^pc_offer, offer}
      assert :ok = Specter.set_local_description(specter, pc_offer, offer)
      assert_receive {:ok, ^pc_offer, :set_local_description}

      assert :ok = Specter.set_remote_description(specter, pc_answer, offer)
      assert_receive {:ok, ^pc_answer, :set_remote_description}

      assert :ok = Specter.create_answer(specter, pc_answer)
      assert_receive {:answer, ^pc_answer, answer}
      assert :ok = Specter.set_local_description(specter, pc_answer, answer)
      assert_receive {:ok, ^pc_answer, :set_local_description}

      assert_receive {:ice_candidate, ^pc_offer, candidate}
      assert :ok = Specter.add_ice_candidate(specter, pc_answer, candidate)
      assert_receive {:ok, ^pc_answer, :add_ice_candidate}

      assert :ok = Specter.set_remote_description(specter, pc_offer, answer)
      assert_receive {:ok, ^pc_offer, :set_remote_description}

      assert_receive {:ice_candidate, ^pc_answer, candidate}
      assert :ok = Specter.add_ice_candidate(specter, pc_offer, candidate)
      assert_receive {:ok, ^pc_offer, :add_ice_candidate}
    end
  end

  describe "current_local_description" do
    setup [:initialize_specter, :init_api, :init_peer_connection]

    test "returns an error when peer connection does not exist", %{specter: specter} do
      assert {:error, :not_found} = Specter.current_local_description(specter, UUID.uuid4())
    end

    test "sends the current local description back to elixir", %{
      specter: specter,
      peer_connection: pc
    } do
      assert :ok = Specter.current_local_description(specter, pc)
      assert_receive {:current_local_description, ^pc, nil}

      assert :ok = Specter.create_offer(specter, pc)
      assert_receive {:offer, ^pc, offer}

      assert :ok = Specter.set_local_description(specter, pc, offer)
      assert_receive {:ok, ^pc, :set_local_description}

      ## asserting non-nil current desc requires successful ICE negotiation
      # assert :ok = Specter.current_local_description(specter, pc)
      # refute_receive {:current_local_description, ^pc, nil}
    end
  end

  describe "current_remote_description" do
    setup [
      :initialize_specter,
      :init_api,
      :init_peer_connection,
      :create_data_channel,
      :create_offer
    ]

    test "returns an error when peer connection does not exist", %{specter: specter} do
      assert {:error, :not_found} = Specter.current_remote_description(specter, UUID.uuid4())
    end

    test "sends the current remote description back to elixir", %{
      specter: specter,
      offer: offer
    } do
      api = init_api(specter)
      pc = init_peer_connection(specter, api)
      assert :ok = Specter.current_remote_description(specter, pc)
      assert_receive {:current_remote_description, ^pc, nil}

      assert :ok = Specter.set_remote_description(specter, pc, offer)
      assert_receive {:ok, ^pc, :set_remote_description}

      ## asserting non-nil current desc requires successful ICE negotiation
      # assert :ok = Specter.current_remote_description(specter, pc)
      # refute_receive {:current_remote_description, ^pc, nil}
    end
  end

  describe "new_api" do
    setup :initialize_specter

    test "returns a UUID, and consumes the media engine and registry", %{specter: specter} do
      assert {:ok, media_engine} = Specter.new_media_engine(specter)
      assert {:ok, registry} = Specter.new_registry(specter, media_engine)
      assert {:ok, api_builder} = Specter.new_api(specter, media_engine, registry)
      assert is_binary(api_builder)
      assert String.match?(api_builder, @uuid_regex)

      refute Specter.media_engine_exists?(specter, media_engine)
      refute Specter.registry_exists?(specter, registry)
    end

    test "returns {:error, :not_found} when given a random media engine id", %{specter: specter} do
      assert {:ok, media_engine} = Specter.new_media_engine(specter)
      assert {:ok, registry} = Specter.new_registry(specter, media_engine)

      assert {:error, :not_found} = Specter.new_api(specter, UUID.uuid4(), registry)
    end

    test "returns {:error, :not_found} when given a random registry id", %{specter: specter} do
      assert {:ok, media_engine} = Specter.new_media_engine(specter)
      assert {:ok, _registry} = Specter.new_registry(specter, media_engine)

      assert {:error, :not_found} = Specter.new_api(specter, media_engine, UUID.uuid4())
    end
  end

  describe "new_media_engine" do
    setup :initialize_specter

    test "returns a UUID", %{specter: specter} do
      assert {:ok, media_engine} = Specter.new_media_engine(specter)
      assert is_binary(media_engine)
      assert String.match?(media_engine, @uuid_regex)
    end
  end

  describe "new_registry" do
    setup :initialize_specter

    test "returns a UUID", %{specter: specter} do
      assert {:ok, media_engine} = Specter.new_media_engine(specter)
      assert {:ok, registry} = Specter.new_registry(specter, media_engine)
      assert is_binary(registry)
      assert String.match?(registry, @uuid_regex)
    end

    test "returns {:error, :not_found} when given a random media engine id", %{specter: specter} do
      assert {:error, :not_found} = Specter.new_registry(specter, UUID.uuid4())
    end
  end

  describe "new_peer_connection" do
    setup [:initialize_specter, :init_api]

    test "returns a UUID, then sends a :peer_connection_ready", %{specter: specter, api: api} do
      assert {:ok, pc} = Specter.new_peer_connection(specter, api)
      assert_receive {:peer_connection_ready, ^pc}

      assert is_binary(pc)
      assert String.match?(pc, @uuid_regex)
    end

    test "returns {:error, :not_found} when given a random api id", %{specter: specter} do
      assert {:error, :not_found} = Specter.new_peer_connection(specter, UUID.uuid4())
    end
  end

  describe "local_description" do
    setup [:initialize_specter, :init_api, :init_peer_connection]

    test "returns an error when peer connection does not exist", %{specter: specter} do
      assert {:error, :not_found} = Specter.local_description(specter, UUID.uuid4())
    end

    test "sends the pending local description back to elixir before ICE finishes", %{
      specter: specter,
      peer_connection: pc
    } do
      assert :ok = Specter.local_description(specter, pc)
      assert_receive {:local_description, ^pc, nil}

      assert :ok = Specter.create_offer(specter, pc)
      assert_receive {:offer, ^pc, offer}

      assert :ok = Specter.set_local_description(specter, pc, offer)
      assert_receive {:ok, ^pc, :set_local_description}

      assert :ok = Specter.local_description(specter, pc)
      assert_receive {:local_description, ^pc, ^offer}
    end
  end

  describe "media_engine_exists?" do
    setup :initialize_specter

    test "is false when the media engine does not exist", %{specter: specter} do
      refute Specter.media_engine_exists?(specter, UUID.uuid4())
    end

    test "is true when the media engine exists", %{specter: specter} do
      assert {:ok, media_engine} = Specter.new_media_engine(specter)
      assert Specter.media_engine_exists?(specter, media_engine)
    end
  end

  describe "peer_connection_exists?" do
    setup [:initialize_specter, :init_api]

    test "is false when the peer connection does not exist", %{specter: specter} do
      refute Specter.peer_connection_exists?(specter, UUID.uuid4())
    end

    test "is true when the peer connection exists", %{specter: specter, api: api} do
      assert {:ok, pc} = Specter.new_peer_connection(specter, api)
      refute Specter.peer_connection_exists?(specter, pc)
      assert_receive {:peer_connection_ready, ^pc}

      assert Specter.peer_connection_exists?(specter, pc)
    end
  end

  describe "pending_local_description" do
    setup [:initialize_specter, :init_api, :init_peer_connection]

    test "returns an error when peer connection does not exist", %{specter: specter} do
      assert {:error, :not_found} = Specter.pending_local_description(specter, UUID.uuid4())
    end

    test "sends the pending local description back to elixir before ICE finishes", %{
      specter: specter,
      peer_connection: pc
    } do
      assert :ok = Specter.pending_local_description(specter, pc)
      assert_receive {:pending_local_description, ^pc, nil}

      assert :ok = Specter.create_offer(specter, pc)
      assert_receive {:offer, ^pc, offer}

      assert :ok = Specter.set_local_description(specter, pc, offer)
      assert_receive {:ok, ^pc, :set_local_description}

      assert :ok = Specter.pending_local_description(specter, pc)
      assert_receive {:pending_local_description, ^pc, ^offer}
    end
  end

  describe "pending_remote_description" do
    setup [
      :initialize_specter,
      :init_api,
      :init_peer_connection,
      :create_data_channel,
      :create_offer
    ]

    test "returns an error when peer connection does not exist", %{specter: specter} do
      assert {:error, :not_found} = Specter.pending_remote_description(specter, UUID.uuid4())
    end

    test "sends the pending remote description back to elixir before ICE finishes", %{
      specter: specter,
      offer: offer
    } do
      api = init_api(specter)
      pc = init_peer_connection(specter, api)
      assert :ok = Specter.pending_remote_description(specter, pc)
      assert_receive {:pending_remote_description, ^pc, nil}

      assert :ok = Specter.set_remote_description(specter, pc, offer)
      assert_receive {:ok, ^pc, :set_remote_description}

      assert :ok = Specter.pending_remote_description(specter, pc)
      assert_receive {:pending_remote_description, ^pc, ^offer}
    end
  end

  describe "registry_exists?" do
    setup :initialize_specter

    test "is false when the registry does not exist", %{specter: specter} do
      refute Specter.registry_exists?(specter, UUID.uuid4())
    end

    test "is true when the media engine exists", %{specter: specter} do
      assert {:ok, media_engine} = Specter.new_media_engine(specter)
      assert {:ok, registry} = Specter.new_registry(specter, media_engine)
      assert Specter.registry_exists?(specter, registry)
    end
  end

  describe "create_offer" do
    setup [:initialize_specter, :init_api, :init_peer_connection]

    test "returns an error when peer connection does not exist", %{specter: specter} do
      assert {:error, :not_found} = Specter.create_offer(specter, UUID.uuid4())
    end

    test "returns :ok and then sends an offer json", %{
      specter: specter,
      peer_connection: peer_connection
    } do
      assert :ok = Specter.create_offer(specter, peer_connection)
      assert_receive {:offer, ^peer_connection, offer}
      assert is_binary(offer)

      assert {:ok, offer_json} = Jason.decode(offer)
      assert %{"type" => "offer", "sdp" => _sdp} = offer_json
    end

    test "returns :ok with VAD", %{
      specter: specter,
      peer_connection: peer_connection
    } do
      assert :ok = Specter.create_offer(specter, peer_connection, voice_activity_detection: true)
      assert_receive {:offer, ^peer_connection, offer}
      assert is_binary(offer)

      # assert offer is different... somehow? maybe after more interactions are available, the generated
      # SDP will actually be different.
    end

    test "returns error with ice_restart before ICE has started", %{
      specter: specter,
      peer_connection: peer_connection
    } do
      assert :ok = Specter.create_offer(specter, peer_connection, ice_restart: true)
      assert_receive {:offer_error, ^peer_connection, "ICEAgent does not exist"}
    end
  end

  describe "create_data_channel" do
    setup [:initialize_specter, :init_api, :init_peer_connection]

    test "returns an error when peer connection does not exist", %{specter: specter} do
      assert {:error, :not_found} = Specter.create_data_channel(specter, UUID.uuid4(), "foo")
    end

    test "sends an :ok message to elixir, and adds it to offers", %{
      specter: specter,
      peer_connection: peer_connection
    } do
      assert :ok = Specter.create_offer(specter, peer_connection)
      assert_receive {:offer, ^peer_connection, offer}
      refute String.contains?(offer, "ice-ufrag")
      refute String.contains?(offer, "ice-pwd")
      refute String.contains?(offer, "webrtc-datachannel")

      assert :ok = Specter.create_data_channel(specter, peer_connection, "foo")
      assert_receive {:data_channel_created, ^peer_connection}

      assert :ok = Specter.create_offer(specter, peer_connection)
      assert_receive {:offer, ^peer_connection, offer}
      assert {:ok, offer_json} = Jason.decode(offer)

      assert String.contains?(offer_json["sdp"], "ice-ufrag")
      assert String.contains?(offer_json["sdp"], "ice-pwd")

      assert String.contains?(
               offer_json["sdp"],
               "m=application 9 UDP/DTLS/SCTP webrtc-datachannel"
             )
    end
  end

  describe "create_answer" do
    setup [:initialize_specter, :init_api, :init_peer_connection]

    test "returns an error when peer connection does not exist", %{specter: specter} do
      assert {:error, :not_found} = Specter.create_answer(specter, UUID.uuid4())
    end

    test "returns :ok and then sends an answer", %{
      specter: specter,
      peer_connection: peer_connection
    } do
      api = init_api(specter)
      pc_offer = init_peer_connection(specter, api)
      assert :ok = Specter.create_data_channel(specter, pc_offer, "foo")
      assert_receive {:data_channel_created, ^pc_offer}
      assert :ok = Specter.create_offer(specter, pc_offer)
      assert_receive {:offer, ^pc_offer, offer}

      assert :ok = Specter.set_remote_description(specter, peer_connection, offer)
      assert_receive {:ok, ^peer_connection, :set_remote_description}

      assert :ok = Specter.create_answer(specter, peer_connection)
      assert_receive {:answer, ^peer_connection, answer}
      assert is_binary(answer)

      assert {:ok, answer_json} = Jason.decode(answer)
      assert %{"type" => "answer", "sdp" => _sdp} = answer_json
    end
  end

  describe "remote_description" do
    setup [
      :initialize_specter,
      :init_api,
      :init_peer_connection,
      :create_data_channel,
      :create_offer
    ]

    test "returns an error when peer connection does not exist", %{specter: specter} do
      assert {:error, :not_found} = Specter.remote_description(specter, UUID.uuid4())
    end

    test "sends the pending remote description back to elixir before ICE finishes", %{
      specter: specter,
      offer: offer
    } do
      api = init_api(specter)
      pc = init_peer_connection(specter, api)
      assert :ok = Specter.remote_description(specter, pc)
      assert_receive {:remote_description, ^pc, nil}

      assert :ok = Specter.set_remote_description(specter, pc, offer)
      assert_receive {:ok, ^pc, :set_remote_description}

      assert :ok = Specter.remote_description(specter, pc)
      assert_receive {:remote_description, ^pc, ^offer}
    end
  end

  describe "set_local_description" do
    setup [:initialize_specter, :init_api, :init_peer_connection]

    test "returns an error when peer connection does not exist", %{specter: specter} do
      assert {:error, :not_found} = Specter.set_local_description(specter, UUID.uuid4(), "")
    end

    test "returns an error when given invalid json", %{specter: specter, peer_connection: pc} do
      assert {:error, :invalid_json} = Specter.set_local_description(specter, pc, "{blah:")
    end

    test "sends :ok when given a valid offer", %{specter: specter, peer_connection: pc} do
      assert :ok = Specter.create_offer(specter, pc)
      assert_receive {:offer, ^pc, offer}

      assert :ok = Specter.set_local_description(specter, pc, offer)
      assert_receive {:ok, ^pc, :set_local_description}
    end

    test "sends :invalid_local_description when given an invalid session", %{
      specter: specter,
      peer_connection: pc
    } do
      assert :ok = Specter.set_local_description(specter, pc, ~S[{"type":"offer","sdp":"derp"}])
      assert_receive {:invalid_local_description, ^pc, "SdpInvalidSyntax: derp"}
    end
  end

  describe "set_remote_description" do
    setup [:initialize_specter, :init_api, :init_peer_connection]

    @valid_offer_sdp """
    v=0
    o=- 2927307686215094172 2 IN IP4 127.0.0.1
    s=-
    t=0 0
    a=extmap-allow-mixed
    a=msid-semantic: WMS
    a=ice-ufrag:ZZZZ
    a=ice-pwd:AU/SQPupllyS0SDG/eRWDCfA
    a=fingerprint:sha-256 B7:D5:86:B0:92:C6:A6:03:80:C8:59:47:25:EC:FF:3F:57:F5:97:EF:76:B9:AA:14:B7:8C:C9:B3:4D:CA:1B:0A
    """
    @valid_offer Jason.encode!(%{type: "offer", sdp: @valid_offer_sdp})

    test "returns :ok when given an offer", %{specter: specter, peer_connection: peer_connection} do
      assert :ok = Specter.set_remote_description(specter, peer_connection, @valid_offer)
      assert_receive {:ok, ^peer_connection, :set_remote_description}
      refute_received {:error, ^peer_connection, :invalid_remote_description}
    end

    test "sends an error message when SDP in invalid", %{specter: specter, peer_connection: pc} do
      assert :ok =
               Specter.set_remote_description(
                 specter,
                 pc,
                 ~S[{"type":"offer","sdp":"Hello world"}]
               )

      assert_receive {:invalid_remote_description, ^pc, "SdpInvalidSyntax: Hello world"}
    end

    test "returns an error when peer connection does not exist", %{specter: specter} do
      assert {:error, :not_found} =
               Specter.set_remote_description(specter, UUID.uuid4(), @valid_offer)
    end

    test "returns an error when given invalid json", %{specter: specter, peer_connection: pc} do
      assert {:error, :invalid_json} =
               Specter.set_remote_description(specter, pc, ~S[{"type:"offer","sd}])
    end
  end

  describe "on_ice_candidate" do
    setup [:initialize_specter, :init_api, :init_peer_connection]

    test "sends candidates as they are generated", %{specter: specter, peer_connection: pc_offer} do
      api = init_api(specter)
      pc_answer = init_peer_connection(specter, api)

      assert :ok = Specter.create_data_channel(specter, pc_offer, "foo")
      assert_receive {:data_channel_created, ^pc_offer}
      assert :ok = Specter.create_offer(specter, pc_offer)
      assert_receive {:offer, ^pc_offer, offer}
      assert :ok = Specter.set_local_description(specter, pc_offer, offer)
      assert_receive {:ok, ^pc_offer, :set_local_description}

      assert :ok = Specter.set_remote_description(specter, pc_answer, offer)
      assert_receive {:ok, ^pc_answer, :set_remote_description}

      assert :ok = Specter.create_answer(specter, pc_answer)
      assert_receive {:answer, ^pc_answer, answer}
      assert :ok = Specter.set_local_description(specter, pc_answer, answer)
      assert_receive {:ok, ^pc_answer, :set_local_description}

      assert_receive {:ice_candidate, ^pc_offer, _candidate}
      assert_receive {:ice_candidate, ^pc_answer, _candidate}
    end
  end
end
