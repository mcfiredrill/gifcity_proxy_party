defmodule GifcityProxyPartyWeb.ProxyTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias GifcityProxyParty.FakeHTTP
  @endpoint GifcityProxyPartyWeb.Endpoint
  @capture "20091019045002/http://www.geocities.com/jiffyjamz/hello.gif"
  @gif Base.decode64!("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")

  setup do
    start_supervised!(FakeHTTP)
    :ok
  end

  test "parses search terms from the URL query string" do
    FakeHTTP.stub(fn url, _ ->
      assert URI.decode_query(URI.parse(url).query)["q"] == "pizza & soda"
      {:ok, "[]"}
    end)

    assert %{"data" => []} =
             build_conn() |> get("/search?q=pizza%20%26%20soda") |> json_response(200)

    assert length(FakeHTTP.calls()) == 1
  end

  test "search caps results, produces stable chat-compatible URLs and caches normalized queries" do
    FakeHTTP.stub(fn url, _ ->
      assert URI.decode_query(URI.parse(url).query)["q"] == "simpsons"

      rows =
        for i <- 1..30,
            do: %{"gif" => String.replace(@capture, "hello", "hello#{i}"), "url_text" => "hello"}

      {:ok, Jason.encode!(rows)}
    end)

    first = build_conn() |> get("/search", q: " simpsons ") |> json_response(200)
    assert length(first["data"]) == 20
    assert first["pagination"]["count"] == 20
    [gif | _] = first["data"]
    assert gif["type"] == "gif"
    assert gif["url"] == gif["images"]["original"]["url"]
    assert gif["url"] == gif["images"]["fixed_width"]["url"]
    assert URI.parse(gif["url"]).host == "localhost"
    assert build_conn() |> get("/search", q: "simpsons") |> json_response(200) == first
    assert length(FakeHTTP.calls()) == 1
  end

  test "rejects missing, blank, oversized and structured queries without an upstream call" do
    for params <- [%{}, %{q: " "}, %{q: String.duplicate("x", 201)}, %{q: ["cat"]}] do
      assert build_conn() |> get("/search", params) |> json_response(400)
    end

    assert FakeHTTP.calls() == []
  end

  test "downloads GIF from raw Wayback, caches it and rejects forged image URLs" do
    FakeHTTP.stub(fn url, _ ->
      if String.contains?(url, "gifsearch") do
        {:ok, Jason.encode!([%{"gif" => @capture}])}
      else
        assert url ==
                 "https://web.archive.org/web/20091019045002id_/http://www.geocities.com/jiffyjamz/hello.gif"

        {:ok, @gif}
      end
    end)

    %{"data" => [gif]} = build_conn() |> get("/search", q: "download") |> json_response(200)
    path = URI.parse(gif["url"]).path
    conn = build_conn() |> get(path)
    assert response(conn, 200) == @gif
    assert get_resp_header(conn, "content-type") == ["image/gif"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert build_conn() |> get(path) |> response(200) == @gif
    assert length(FakeHTTP.calls()) == 2
    assert build_conn() |> get("/images/forged.gif") |> json_response(404)
    assert length(FakeHTTP.calls()) == 2
  end

  test "does not cache failed searches and skips malformed rows" do
    FakeHTTP.stub(fn _, _ -> {:ok, "not json"} end)
    assert build_conn() |> get("/search", q: "retry") |> json_response(502)

    FakeHTTP.stub(fn _, _ ->
      {:ok, Jason.encode!([%{"gif" => "http://localhost/secret"}, nil])}
    end)

    assert %{"data" => []} = build_conn() |> get("/search", q: "retry") |> json_response(200)
    assert length(FakeHTTP.calls()) == 2
  end

  test "rejects HTML masquerading as an archived GIF" do
    FakeHTTP.stub(fn url, _ ->
      if String.contains?(url, "gifsearch"),
        do: {:ok, Jason.encode!([%{"gif" => String.replace(@capture, "hello", "bad")}])},
        else: {:ok, "<html>rate limited</html>"}
    end)

    %{"data" => [gif]} = build_conn() |> get("/search", q: "html") |> json_response(200)
    assert build_conn() |> get(URI.parse(gif["url"]).path) |> json_response(502)
  end

  test "CORS permits Datafruits and local development, excludes other origins" do
    for origin <- ["https://datafruits.fm", "https://www.datafruits.fm"] do
      conn = build_conn() |> put_req_header("origin", origin) |> get("/health")
      assert get_resp_header(conn, "access-control-allow-origin") == [origin]
      assert get_resp_header(conn, "vary") == ["origin"]

      assert build_conn()
             |> put_req_header("origin", origin)
             |> options("/search")
             |> response(204) == ""
    end

    conn = build_conn() |> put_req_header("origin", "https://example.com") |> get("/health")
    assert get_resp_header(conn, "access-control-allow-origin") == []
  end
end
