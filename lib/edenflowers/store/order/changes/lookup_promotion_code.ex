defmodule Edenflowers.Store.Order.LookupPromotionCode do
  @moduledoc """
  Looks up a promotion by its code and assigns it to the order.

  If the code is valid and the promotion is active, the promotion_id
  is set on the order. If the code is invalid or the promotion is
  inactive/expired, an error is added to the changeset.
  """
  use Ash.Resource.Change
  use Gettext, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Store.Promotion

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case Ash.Changeset.get_argument(changeset, :code) do
        nil ->
          Ash.Changeset.add_error(changeset, %Ash.Error.Changes.Required{field: :code})

        code ->
          case Promotion.get_by_code(code) do
            {:ok, promotion} ->
              Ash.Changeset.force_change_attributes(changeset, promotion_id: promotion.id)

            {:error, _error} ->
              Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
                field: :code,
                message: gettext("Invalid code")
              })
          end
      end
    end)
  end
end
