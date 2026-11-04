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
    case Phoenix.Token.verify(EdenflowersWeb.Endpoint, @state_salt, state, max_age: 3600) do
      {:ok, user_id} when user_id == user.id ->
        connect(conn, code, user)

      {:ok, other_user_id} ->
        Logger.error("The bank login was started by another user: #{other_user_id}")
        failed(conn)

      {:error, reason} ->
        Logger.error("The bank login's state didn't verify: #{inspect(reason)}")
        failed(conn)
    end
  end

  def callback(%{assigns: %{current_user: %{admin: true}}} = conn, params) do
    Logger.error("The bank returned without a code: #{inspect(Map.take(params, ["error", "error_description"]))}")
    failed(conn)
  end

  def callback(conn, _params), do: send_resp(conn, :not_found, "Not found")

  defp connect(conn, code, user) do
    case Edenflowers.Bank.connect_bank(code, actor: user) do
      {:ok, _connection} ->
        conn
        |> put_flash(:success, ~t"Bank connected.")
        |> redirect(to: ~p"/admin/expenses")

      {:error, error} ->
        Logger.error("Connecting the bank failed: #{inspect(error)}")
        failed(conn)
    end
  end

  defp failed(conn) do
    conn
    |> put_flash(:error, ~t"The bank wasn't connected. Please try again.")
    |> redirect(to: ~p"/admin/expenses")
  end
end
