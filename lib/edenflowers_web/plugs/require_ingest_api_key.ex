defmodule EdenflowersWeb.Plugs.RequireIngestApiKey do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    expected = Application.fetch_env!(:edenflowers, :ingest_api_key)

    case get_req_header(conn, "x-api-key") do
      [^expected] ->
        conn

      _ ->
        conn
        |> send_resp(401, "Unauthorized")
        |> halt()
    end
  end
end
