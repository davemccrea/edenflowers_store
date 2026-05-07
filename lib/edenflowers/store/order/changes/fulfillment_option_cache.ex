defmodule Edenflowers.Store.Order.Changes.FulfillmentOptionCache do
  @moduledoc """
  Shared lookup for changes on `save_step_3` that all consume the
  `FulfillmentOption` referenced by `fulfillment_option_id`. The first
  caller fetches and stashes the option via `Ash.Changeset.put_context/3`;
  later callers reuse the cached value, so a single submit performs at
  most one `Ash.get/2` regardless of how many changes consume the option.
  """
  alias Edenflowers.Store.FulfillmentOption

  @spec fetch(Ash.Changeset.t(), term()) ::
          {:ok, FulfillmentOption.t(), Ash.Changeset.t()} | {:error, term()}
  def fetch(changeset, id) do
    case changeset.context[:fulfillment_option] do
      %{id: ^id} = option -> {:ok, option, changeset}
      _ -> fetch_and_cache(changeset, id)
    end
  end

  defp fetch_and_cache(changeset, id) do
    case Ash.get(FulfillmentOption, id, authorize?: false) do
      {:ok, option} ->
        {:ok, option, Ash.Changeset.put_context(changeset, :fulfillment_option, option)}

      {:error, _} = error ->
        error
    end
  end
end
