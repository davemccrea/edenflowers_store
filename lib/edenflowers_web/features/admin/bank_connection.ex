defmodule EdenflowersWeb.Admin.BankConnection do
  @moduledoc """
  Starts the bank connection from the overview or the account page.
  """
  use EdenflowersWeb, :verified_routes
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  require Logger

  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  alias Edenflowers.Bank
  alias EdenflowersWeb.Admin.BankController

  @doc "Redirects to the bank, or flashes an error when it can't be reached."
  def connect(socket) do
    user = socket.assigns.current_user
    state = BankController.sign_state(user)

    case Bank.bank_authorization_url(state, url(~p"/admin/bank/callback"), actor: user) do
      {:ok, url} ->
        {:noreply, redirect(socket, external: url)}

      {:error, error} ->
        Logger.error("Starting a bank connection failed: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, ~t"The bank couldn't be reached. Please try again.")}
    end
  end
end
