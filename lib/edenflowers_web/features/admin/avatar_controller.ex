defmodule EdenflowersWeb.Admin.AvatarController do
  use EdenflowersWeb, :controller

  def show(conn, _params) do
    with %{admin: true} = user <- conn.assigns[:current_user],
         {:ok, %{avatar: avatar, avatar_content_type: type}} when is_binary(avatar) <-
           Ash.load(user, :avatar, actor: user) do
      etag = ~s("#{:erlang.phash2(avatar)}")

      conn =
        conn
        |> put_resp_header("cache-control", "private, no-cache")
        |> put_resp_header("etag", etag)

      if etag in get_req_header(conn, "if-none-match") do
        send_resp(conn, :not_modified, "")
      else
        conn |> put_resp_content_type(type, nil) |> send_resp(:ok, avatar)
      end
    else
      _ -> send_resp(conn, :not_found, "Not found")
    end
  end
end
