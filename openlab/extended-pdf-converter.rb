require 'asciidoctor-pdf' unless defined? ::Asciidoctor::Pdf

module AsciidoctorPdfExtensions

  def layout_title_page doc
    super
    theme_font :footer, level: 2 do
        move_cursor_to page_margin_bottom
        title_footer = apply_subs_discretely doc, @theme.footer_title_center_content, subs: [:attributes]
        text title_footer, align: :center
    end

  end
end
Asciidoctor::Pdf::Converter.prepend AsciidoctorPdfExtensions
