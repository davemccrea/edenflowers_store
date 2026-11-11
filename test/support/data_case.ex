defmodule Edenflowers.DataCase do
  @moduledoc """
  Provides SQL sandbox setup, Oban test helpers and default external-service
  stubs for tests that use the application's data layer.

  Database changes are rolled back after each test. Use `async: true` for
  isolated tests; tests that change global application configuration or shared
  singleton rows must run synchronously.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      use Oban.Testing, repo: Edenflowers.Repo
    end
  end

  setup tags do
    Edenflowers.DataCase.setup_sandbox(tags)
    Edenflowers.DataCase.stub_card_lookup()
    Edenflowers.DataCase.stub_papra_update()
    :ok
  end

  @doc """
  Starts a sandbox owner and stops it when the test exits. Synchronous tests
  share the connection with other processes; async tests keep it isolated.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Edenflowers.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  @doc """
  Stubs the Stripe lookup used to display a subscription's saved card. Returns
  only the payment-method ID by default; tests that need specific card details
  or call verification can set their own Mox expectation.
  """
  def stub_card_lookup do
    Mox.stub(Edenflowers.External.StripeAPI.Mock, :retrieve_payment_method, fn id -> {:ok, %{id: id}} end)
  end

  @doc """
  Accepts Papra document updates when an expense is saved, without contacting
  Papra. Tests that need to verify the update can set their own Mox expectation.
  """
  def stub_papra_update do
    Mox.stub(Edenflowers.External.PapraAPI.Mock, :update_document, fn _document_id, _fields -> :ok end)
  end
end
