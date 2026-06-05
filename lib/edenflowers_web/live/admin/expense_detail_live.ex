defmodule EdenflowersWeb.Admin.ExpenseDetailLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts
  alias Edenflowers.Expenses.Expense

  on_mount {EdenflowersWeb.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    expense = Ash.get!(Expense, id, actor: socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Expense — #{expense.vendor_name || id}")
     |> assign(:expense, expense)
     |> assign(:form, build_form(expense, socket.assigns.current_user))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path}>
      <.admin_page width="narrow">
        <.admin_page_header
          title={@expense.vendor_name || "Unknown vendor"}
          back={~p"/admin/expenses"}
          back_label="Expenses"
        >
          <:actions>
            <span :if={not is_nil(@expense.reviewed_at)} class="badge badge-soft badge-success gap-1">
              <.icon name="hero-check" class="h-3 w-3" /> Reviewed
            </span>
            <button
              :if={is_nil(@expense.reviewed_at)}
              type="button"
              phx-click="mark_reviewed"
              class="btn btn-primary btn-sm"
            >
              Mark as Reviewed
            </button>
          </:actions>
        </.admin_page_header>

        <%!-- Hero: the two facts a reviewer is verifying — the amount, and how much to trust it. --%>
        <section class="mb-10 flex items-end justify-between gap-6 border-b border-base-300/70 pb-8">
          <div>
            <p class="eyebrow text-base-content/40 mb-1">Total Amount</p>
            <p class="font-mono text-4xl font-semibold tabular-nums tracking-tight text-base-content">
              {@expense.total_amount}
              <span class="text-2xl text-base-content/50">
                {@expense.currency |> to_string() |> String.upcase()}
              </span>
            </p>
          </div>
          <div class="text-right">
            <p class="eyebrow text-base-content/40 mb-1.5">Confidence</p>
            <.confidence_badge confidence={@expense.confidence} />
          </div>
        </section>

        <section class="mb-10 grid grid-cols-2 gap-x-6 gap-y-5 text-sm">
          <div>
            <dt class="text-xs font-medium text-base-content/45 tracking-wide mb-0.5">Document</dt>
            <dd>
              <a
                href={Edenflowers.Papra.document_url(@expense.document_id)}
                target="_blank"
                rel="noopener"
                class="link link-primary text-sm"
              >
                {@expense.document_id}
              </a>
            </dd>
          </div>
          <.detail_row label="Date" value={@expense.date} />
          <.detail_row label="VAT Amount" value={@expense.vat_amount} />
          <.detail_row label="VAT Number" value={@expense.vendor_vat_number} />
          <.detail_row label="Category" value={@expense.category} />
          <.detail_row
            label="Processed"
            value={@expense.processed_at && Calendar.strftime(@expense.processed_at, "%d %b %Y, %H:%M UTC")}
          />
          <.detail_row
            label="Reviewed"
            value={@expense.reviewed_at && Calendar.strftime(@expense.reviewed_at, "%d %b %Y, %H:%M UTC")}
          />
          <div class="col-span-2">
            <.detail_row label="Description" value={@expense.description} />
          </div>
        </section>

        <section>
          <h2 class="text-sm font-semibold text-base-content/45 mb-4">Correct Extracted Data</h2>
          <.form for={@form} phx-submit="correct" phx-change="validate">
            <div class="grid grid-cols-2 gap-4">
              <.input field={@form[:vendor_name]} type="text" label="Vendor Name" class="input input-bordered input-sm w-full" />
              <.input field={@form[:vendor_vat_number]} type="text" label="VAT Number" class="input input-bordered input-sm w-full" />
              <.input field={@form[:date]} type="date" label="Date" class="input input-bordered input-sm w-full" />
              <.input field={@form[:currency]} type="select" label="Currency" options={["EUR": :eur, "SEK": :sek]} class="select select-bordered select-sm w-full" />
              <.input field={@form[:total_amount]} type="text" label="Total Amount" class="input input-bordered input-sm w-full" />
              <.input field={@form[:vat_amount]} type="text" label="VAT Amount" class="input input-bordered input-sm w-full" />
              <.input
                field={@form[:category]}
                type="select"
                label="Category"
                options={[
                  "Office Supplies": :office_supplies,
                  "Travel": :travel,
                  "Meals": :meals,
                  "Software": :software,
                  "Marketing": :marketing,
                  "Utilities": :utilities,
                  "Professional Services": :professional_services,
                  "Other": :other
                ]}
                class="select select-bordered select-sm w-full"
              />
              <div class="col-span-2">
                <.input field={@form[:description]} type="textarea" label="Description" class="textarea textarea-bordered textarea-sm w-full" />
              </div>
            </div>
            <div class="mt-6">
              <button type="submit" class="btn btn-primary btn-sm">Save Corrections</button>
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
         |> put_flash(:info, "Expense marked as reviewed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not mark expense as reviewed.")}
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
         |> put_flash(:info, "Expense updated.")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  defp build_form(expense, actor) do
    AshPhoenix.Form.for_update(expense, :correct, actor: actor) |> to_form()
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp detail_row(assigns) do
    ~H"""
    <div>
      <dt class="text-xs font-medium text-base-content/45 tracking-wide mb-0.5">{@label}</dt>
      <dd class="text-base-content">{@value || "—"}</dd>
    </div>
    """
  end
end
