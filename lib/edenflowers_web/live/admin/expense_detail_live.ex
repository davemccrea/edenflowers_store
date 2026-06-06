defmodule EdenflowersWeb.Admin.ExpenseDetailLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts
  alias Edenflowers.Expenses.Expense
  alias Edenflowers.Format

  on_mount {EdenflowersWeb.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Ash.get(Expense, id, actor: socket.assigns.current_user) do
      {:ok, expense} ->
        {:ok,
         socket
         |> assign(:page_title, ~t"Expense — #{expense.vendor_name || id}")
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
      <.admin_page width="narrow">
        <.admin_page_header
          title={@expense.vendor_name || ~t"Unknown vendor"}
          back={~p"/admin/expenses"}
          back_label={~t"Expenses"}
        >
          <:actions>
            <span :if={not is_nil(@expense.reviewed_at)} class="badge badge-soft badge-sm badge-success gap-1">
              <.icon name="hero-check" class="h-3 w-3" /> {~t"Reviewed"}
            </span>
            <button
              :if={is_nil(@expense.reviewed_at)}
              type="button"
              phx-click="mark_reviewed"
              class="btn btn-primary btn-sm"
            >
              {~t"Mark as Reviewed"}
            </button>
          </:actions>
        </.admin_page_header>

        <section class="border-base-300/70 mb-8 flex flex-col gap-4 border-b pb-6 sm:mb-10 sm:flex-row sm:items-end sm:justify-between sm:gap-6 sm:pb-8">
          <div class="min-w-0">
            <p class="eyebrow text-base-content/65 mb-1">{~t"Total Amount"}</p>
            <p class="text-base-content truncate text-3xl font-semibold tabular-nums tracking-tight sm:text-4xl">
              {Format.amount(@expense.total_amount, @expense.currency, @locale) || "—"}
            </p>
          </div>
          <div class="sm:text-right">
            <p class="eyebrow text-base-content/65 mb-1.5">{~t"Confidence"}</p>
            <.confidence_badge confidence={@expense.confidence} />
          </div>
        </section>

        <section class="text-base-content/65 mb-10 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
          <span>
            {~t"Document"}
            <a
              href={Edenflowers.Papra.document_url(@expense.document_id)}
              target="_blank"
              rel="noopener"
              class="link link-primary"
            >
              {@expense.document_id}
            </a>
          </span>
          <span :if={@expense.processed_at} aria-hidden="true">·</span>
          <span :if={@expense.processed_at}>
            {~t"Processed"} {Format.datetime(@expense.processed_at, @locale)}
          </span>
          <span :if={@expense.reviewed_at} aria-hidden="true">·</span>
          <span :if={@expense.reviewed_at}>
            {~t"Reviewed"} {Format.datetime(@expense.reviewed_at, @locale)}
          </span>
        </section>

        <section>
          <.form for={@form} phx-submit="correct" phx-change="validate">
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <.input field={@form[:vendor_name]} type="text" label={~t"Vendor Name"} class="input w-full" />
              <.input field={@form[:vendor_vat_number]} type="text" label={~t"VAT Number"} class="input w-full" />
              <.input field={@form[:date]} type="date" label={~t"Date"} class="input w-full" />
              <.input
                field={@form[:currency]}
                type="select"
                label={~t"Currency"}
                options={[EUR: :eur, SEK: :sek]}
                class="select w-full"
              />
              <.input field={@form[:total_amount]} type="text" label={~t"Total Amount"} class="input w-full" />
              <.input field={@form[:vat_amount]} type="text" label={~t"VAT Amount"} class="input w-full" />
              <.input
                field={@form[:category]}
                type="select"
                label={~t"Category"}
                options={[
                  {~t"Office Supplies", :office_supplies},
                  {~t"Travel", :travel},
                  {~t"Meals", :meals},
                  {~t"Software", :software},
                  {~t"Marketing", :marketing},
                  {~t"Utilities", :utilities},
                  {~t"Professional Services", :professional_services},
                  {~t"Other", :other}
                ]}
                class="select w-full"
              />
              <div class="sm:col-span-2">
                <.input field={@form[:description]} type="textarea" label={~t"Description"} class="textarea w-full" />
              </div>
            </div>
            <div class="mt-6">
              <button type="submit" class="btn btn-outline btn-sm w-full sm:w-auto">
                {~t"Save Corrections"}
              </button>
            </div>
          </.form>
        </section>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("mark_reviewed", _params, socket) do
    case Expense.mark_reviewed(socket.assigns.expense, actor: socket.assigns.current_user) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:expense, updated)
         |> put_flash(:info, ~t"Expense marked as reviewed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, ~t"Could not mark expense as reviewed.")}
    end
  end

  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("correct", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:expense, updated)
         |> assign(:form, build_form(updated, socket.assigns.current_user))
         |> put_flash(:info, ~t"Expense updated.")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  defp build_form(expense, actor) do
    AshPhoenix.Form.for_update(expense, :correct, actor: actor) |> to_form()
  end
end
