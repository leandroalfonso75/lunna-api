require "open3"

# Fotos do ERP guardadas otimizadas (decisão do usuário em 27/11/2026): até 1.600 px no lado maior, sem metadados, JPG de
# boa qualidade (WEBP quando a imagem tem transparência), mirando ~150–250 KB. Usa o ImageMagick do servidor; se ele
# não existir ou falhar, guarda a original (nunca perde a foto).
module Erp
  module ImageOptimizer
    MAX_SIDE = 1600
    TARGET_BYTES = 260_000
    QUALITIES = [ 82, 74, 66 ].freeze

    module_function

    # => [bytes, mime]
    def call(bytes, mime)
      bin = binary
      return [ bytes, mime ] unless bin

      alpha = mime == "image/png" || mime == "image/webp" ? alpha?(bin, bytes) : false
      format = alpha ? "webp" : "jpg"
      best = nil
      QUALITIES.each do |q|
        out, status = Open3.capture2(*bin, "-", "-auto-orient", "-resize", "#{MAX_SIDE}x#{MAX_SIDE}>", "-strip",
                                     "-quality", q.to_s, *(format == "jpg" ? [ "-sampling-factor", "4:2:0", "-interlace", "Plane" ] : []),
                                     "#{format}:-", stdin_data: bytes, binmode: true)
        break unless status.success? && out.bytesize.positive?

        best = out
        break if out.bytesize <= TARGET_BYTES
      end
      return [ bytes, mime ] unless best && best.bytesize < bytes.bytesize

      [ best, format == "jpg" ? "image/jpeg" : "image/webp" ]
    rescue StandardError
      [ bytes, mime ]
    end

    def binary
      @binary ||= if system("which magick > /dev/null 2>&1") then [ "magick" ]
      elsif system("which convert > /dev/null 2>&1") then [ "convert" ]
      else false
      end
      @binary || nil
    end

    def alpha?(bin, bytes)
      tool = bin == [ "magick" ] ? [ "magick", "identify" ] : [ "identify" ]
      out, status = Open3.capture2(*tool, "-format", "%[opaque]", "-", stdin_data: bytes, binmode: true)
      status.success? && out.strip.downcase.start_with?("false")
    rescue StandardError
      false
    end
  end
end
