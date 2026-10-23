defmodule EdenflowersWeb.Admin.ExpenseDetailLive do
  @moduledoc """
  Admin page for reviewing, correcting, or deleting an imported expense.
  """

  use EdenflowersWeb, :live_view

  require Logger

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Expenses
  alias Edenflowers.Expenses.Expense
  alias Edenflowers.Format
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Ash.get(Expense, id, actor: socket.assigns.current_user) do
      {:ok, expense} ->
        {:ok,
         socket
         |> assign(:page_title, ~t"Expense: #{expense.vendor_name || id}")
         |> assign(:locale, Localize.get_locale())
         |> assign(:expense, expense)
         |> assign(:form, build_form(expense, socket.assigns.current_user))}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, ~t"Expense not found.")
         |> push_navigate(to: ~p"/admin/expenses")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header
          title={@expense.vendor_name || ~t"Unknown vendor"}
          back={{~t"Expenses", ~p"/admin/expenses"}}
        >
          <:subtitle :if={@expense.reviewed_at}>
            <.badge tone={:success} icon="hero-check">{~t"Reviewed"}</.badge>
          </:subtitle>
          <:menu>
            <.actions_menu id="expense-actions">
              <.actions_menu_button
                menu="expense-actions"
                phx-click="delete"
                data-confirm={~t"Delete this expense? This can't be undone."}
                class="text-error"
              >
                {~t"Delete"}
              </.actions_menu_button>
            </.actions_menu>
          </:menu>
        </.admin_page_header>

        <div class="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_24rem] xl:items-start">
          <.form
            for={@form}
            id="expense-form"
            data-warn-unsaved={~t"You have unsaved changes. Leave without saving?"}
            phx-submit="correct"
            phx-change="validate"
          >
            <.form_section title={~t"Details"}>
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <.input field={@form[:vendor_name]} type="text" label={~t"Vendor name"} class="input w-full" />
                <.input field={@form[:vendor_vat_number]} type="text" label={~t"VAT number"} class="input w-full" />
                <.input field={@form[:date]} type="date" label={~t"Date"} class="input w-full" />
                <.input
                  field={@form[:paid_on]}
                  type="date"
                  label={~t"Paid on"}
                  help={~t"Only needed when it was paid on a different day from its date."}
                  class="input w-full"
                />
                <.input
                  field={@form[:currency]}
                  type="select"
                  label={~t"Currency"}
                  options={[EUR: :eur, SEK: :sek]}
                  class="select w-full"
                />
                <.input
                  field={@form[:total_amount]}
                  type="text"
                  inputmode="decimal"
                  label={~t"Total amount"}
                  class="input w-full"
                />
                <.input
                  field={@form[:vat_amount]}
                  type="text"
                  inputmode="decimal"
                  label={~t"VAT amount"}
                  class="input w-full"
                />
                <.input
                  field={@form[:category]}
                  type="select"
                  label={~t"Category"}
                  options={category_options()}
                  class="select w-full"
                />
                <div class="sm:col-span-2">
                  <.input field={@form[:description]} type="textarea" label={~t"Description"} class="textarea w-full" />
                </div>
              </div>
            </.form_section>
            <div class="mt-6 flex flex-col gap-3 sm:flex-row">
              <%!-- First in source order so Enter in a field saves without marking the expense reviewed. --%>
              <.button
                type="submit"
                variant={if is_nil(@expense.reviewed_at), do: "secondary", else: "primary"}
                phx-disable-with={~t"Saving…"}
                class="w-full sm:w-auto"
              >
                {~t"Save corrections"}
              </.button>
              <.button
                :if={is_nil(@expense.reviewed_at)}
                type="submit"
                name="review"
                value="true"
                variant="primary"
                phx-disable-with={~t"Saving…"}
                class="w-full sm:w-auto"
              >
                {~t"Save and mark reviewed"}
              </.button>
            </div>
          </.form>

          <aside class="order-first flex flex-col gap-6 xl:order-none">
            <.widget id="expense-summary" title={~t"Total amount"}>
              <p class="text-base-content truncate text-3xl font-semibold tabular-nums tracking-tight">
                <span :if={@expense.total_amount && @expense.currency}>
                  {Format.currency_in(@expense.total_amount, @expense.currency, @locale)}
                </span>
                <.blank :if={is_nil(@expense.total_amount) or is_nil(@expense.currency)} />
                <span :if={is_nil(@expense.total_amount) or is_nil(@expense.currency)} class="sr-only">
                  {~t"No amount"}
                </span>
              </p>
              <p class="text-base-content/75 mt-3 flex items-center gap-2 text-sm">
                {~t"Confidence"} <.confidence_badge confidence={@expense.confidence} />
              </p>
            </.widget>

            <.widget id="expense-receipt" title={~t"Receipt"}>
              <div class="space-y-1.5 text-sm">
                <a
                  href={Edenflowers.External.PapraAPI.document_url(@expense.document_id)}
                  target="_blank"
                  rel="noopener"
                  class="link link-primary inline-flex items-center gap-1 font-medium"
                >
                  {~t"Open receipt in Papra"}
                  <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
                </a>
                <p :if={@expense.processed_at} class="text-base-content/75">
                  {~t"Processed"} {Format.datetime(@expense.processed_at, @locale)}
                </p>
                <p :if={@expense.reviewed_at} class="text-base-content/75">
                  {~t"Reviewed"} {Format.datetime(@expense.reviewed_at, @locale)}
                </p>
              </div>
            </.widget>
          </aside>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("correct", %{"form" => params} = submit_params, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, updated} when is_map_key(submit_params, "review") ->
        mark_reviewed(socket, updated)

      {:ok, updated} ->
        {:noreply,
         socket
         |> assign_expense(updated)
         |> push_event("admin-form-saved", %{id: "expense-form"})
         |> put_flash(:info, ~t"Expense updated.")}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:form, form)
         |> put_flash(:error, ~t"The expense wasn't saved. Check the fields marked below.")}
    end
  end

  def handle_event("delete", _params, socket) do
    case Ash.destroy(socket.assigns.expense, actor: socket.assigns.current_user) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, ~t"Expense deleted.")
         |> push_navigate(to: ~p"/admin/expenses")}

      # Deleting removes the tags in Papra first, which is what usually fails.
      {:error, error} ->
        Logger.error("Expense #{socket.assigns.expense.id} not deleted: #{inspect(error)}")

        {:noreply,
         put_flash(
           socket,
           :error,
           ~t"The expense couldn't be deleted because Papra couldn't be reached. Try again later."
         )}
    end
  end

  defp mark_reviewed(socket, expense) do
    case Expenses.mark_expense_reviewed(expense, actor: socket.assigns.current_user) do
      {:ok, reviewed} ->
        {:noreply,
         socket
         |> assign_expense(reviewed)
         |> push_event("admin-form-saved", %{id: "expense-form"})
         |> put_flash(:info, ~t"Expense saved and marked as reviewed.")}

      {:error, error} ->
        Logger.error("Expense #{expense.id} not marked reviewed: #{inspect(error)}")

        {:noreply,
         socket
         |> assign_expense(expense)
         |> push_event("admin-form-saved", %{id: "expense-form"})
         |> put_flash(:error, ~t"Corrections saved, but the expense could not be marked as reviewed.")}
    end
  end

  defp assign_expense(socket, expense) do
    socket
    |> assign(:expense, expense)
    |> assign(:form, build_form(expense, socket.assigns.current_user))
  end

  defp build_form(expense, actor) do
    AshPhoenix.Form.for_update(expense, :correct, actor: actor) |> to_form()
  end
end
