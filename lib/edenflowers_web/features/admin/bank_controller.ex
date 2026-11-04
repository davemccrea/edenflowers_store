defmodule EdenflowersWeb.Admin.BankController do
  @moduledoc """
  Where S-Pankki sends Jennie back after she logs in to connect the shop's
  account. A controller, not a LiveView: the one-time code must be spent once,
  and a LiveView mounts twice.
  """

  use EdenflowersWeb, {:controller, gettext_domain: "admin"}

  require Logger

  @state_salt "bank connection"

  @doc "A state for the bank to hand back, tying the login to the admin who started it."
  def sign_state(user), do: Phoenix.Token.sign(EdenflowersWeb.Endpoint, @state_salt, user.id)

  def callback(%{assigns: %{current_user: %{admin: true} = user}} = conn, %{"state" => state, "code" => code}) do
    with {:ok, user_id} when user_id == user.id <-
           Phoenix.Token.verify(EdenflowersWeb.Endpoint, @state_salt, state, max_age: 3600),
         {:ok, _connection} <- Edenflowers.Bank.connect_bank(code, actor: user) do
      conn
      |> put_flash(:success, ~t"Bank connected.")
      |> redirect(to: ~p"/admin/expenses")
    else
      error ->
        Logger.error("Connecting the bank failed: #{inspect(error)}")
        failed(conn)
    end
  end

  def callback(%{assigns: %{current_user: %{admin: true}}} = conn, params) do
    Logger.error("The bank returned without a code: #{inspect(Map.take(params, ["error", "error_description"]))}")
    failed(conn)
  end

  def callback(conn, _params), do: send_resp(conn, :not_found, "Not found")

  defp failed(conn) do
    conn
    |> put_flash(:error, ~t"The bank wasn't connected. Please try again.")
    |> redirect(to: ~p"/admin/expenses")
  end
end
