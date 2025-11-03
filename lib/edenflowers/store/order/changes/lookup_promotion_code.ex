defmodule Edenflowers.Store.Order.LookupPromotionCode do
  use Ash.Resource.Change
  use Gettext, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Store.Promotion

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case Promotion.get_by_code(changeset.arguments.code) do
        {:ok, promotion} ->
          Ash.Changeset.force_change_attributes(changeset, promotion_id: promotion.id)

        _ ->
          Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
            field: :code,
            message: gettext("Invalid code")
          })
      end
    end)
  end
end
