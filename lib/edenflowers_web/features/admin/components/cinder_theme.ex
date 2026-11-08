defmodule EdenflowersWeb.Admin.CinderTheme do
  @moduledoc """
  Admin table theme extending `:daisy_ui`, with compact controls and visible
  filter labels. Set each filter's `:label`; select prompts use "All".
  """
  use Cinder.Theme

  extends :daisy_ui

  set :container_class, "min-w-0"
  set :controls_class, "card card-sm card-border border-base-content/12 bg-base-100 mb-3 sm:mb-4 overflow-visible"

  set :table_wrapper_class,
      "admin-table-scroll card card-border border-base-content/12 bg-base-100 overflow-x-auto max-w-full"

  set :table_class, "table table-zebra w-full"
  # One line per row at a fixed height, so every admin table reads at the same rhythm
  # whether a cell holds plain text, a badge or an icon button. The vertical padding
  # is trimmed so the tallest of those still fits inside the row height.
  set :row_class, "h-12"
  # daisyUI's thead colour lands just under AA on the table's background.
  set :th_class, "text-base-content/70 text-left font-semibold whitespace-nowrap max-sm:whitespace-normal max-sm:px-2"
  set :td_class, "py-2 align-middle whitespace-nowrap max-sm:px-2"

  set :filter_toggle_class, "cursor-pointer select-none inline-flex items-center gap-1 pointer-coarse:min-h-11"
  set :filter_count_class, "badge badge-primary badge-sm tabular-nums"
  set :filter_container_class, "card-body px-3 py-1.5 sm:p-5"
  # The gap sits on the inputs, not the header, so a collapsed panel has no dead space under its title.
  # Phones get two columns of selects under a full-width search (Cinder renders it first);
  # a lone select left over at the end takes the whole row. Wider screens get equal columns, so rows line up.
  set :filter_inputs_class,
      "fieldset mt-1 mb-1.5 grid grid-cols-2 gap-x-2 gap-y-3 max-sm:*:first:col-span-2 max-sm:*:last:even:col-span-2 sm:my-0 sm:mt-4 sm:grid-cols-[repeat(auto-fill,minmax(14rem,1fr))] sm:gap-4"

  set :filter_input_wrapper_class, "form-control min-w-0"

  set :filter_label_class, "label-text mb-1 block text-xs font-semibold text-base-content/75"

  set :filter_text_input_class, "input input-sm w-full"
  set :filter_date_input_class, "input input-sm w-full sm:w-40"

  set :filter_number_input_class,
      "input input-sm w-full sm:w-24 [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none [-moz-appearance:textfield]"

  set :filter_select_input_class, "select select-sm w-full min-w-0 sm:min-w-44"
  set :filter_range_container_class, "flex flex-col gap-2 sm:flex-row sm:items-center"

  # Outlined rather than the stock `btn-ghost`, which hides a lone "×" until hover.
  # Phones drop the empty placeholder Cinder keeps beside every filter, giving its width back to the control.
  set :filter_clear_button_class,
      "btn btn-outline btn-sm btn-square ml-2 border-base-content/12 text-base-content/75 hover:border-error hover:bg-error/10 hover:text-error max-sm:[&.invisible]:hidden"

  # `pl-10` leaves room for the search icon the renderer overlays.
  set :search_input_class, "input input-sm w-full pl-10"

  # Cinder floats its spinner over the top-right of the whole collection, which lands
  # on the filter card's search box. Later loads keep the rows on screen, so the
  # spinner can sit in the flow under the table and only nudge the pagination row.
  set :loading_overlay_class, "flex justify-end pt-2 pr-1"

  set :pagination_container_class, "flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
  set :pagination_info_class, "text-sm"
  set :pagination_count_class, "text-base-content/75 block text-xs sm:ml-2 sm:inline"
  set :pagination_nav_class, "flex flex-wrap items-center gap-1 sm:flex-nowrap"
  set :page_size_container_class, "flex items-center gap-2"
end
