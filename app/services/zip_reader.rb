# Leitor mínimo de ZIP (sem gem): lê o diretório central e devolve { nome => conteúdo } das entradas guardadas (0) ou
# comprimidas com deflate (8). Usado para os XMLs do download em lote de notas fiscais do ML.
require "zlib"

module ZipReader
  EOCD = "PK\x05\x06".b
  CENTRAL = "PK\x01\x02".b
  LOCAL = "PK\x03\x04".b

  def self.entries(data)
    data = data.b
    eocd = data.rindex(EOCD) or raise ArgumentError, "arquivo ZIP inválido"
    count = data[eocd + 10, 2].unpack1("v")
    offset = data[eocd + 16, 4].unpack1("V")
    out = {}
    count.times do
      raise ArgumentError, "diretório central inválido" unless data[offset, 4] == CENTRAL

      method, = data[offset + 10, 2].unpack("v")
      csize = data[offset + 20, 4].unpack1("V")
      name_len, extra_len, comment_len = data[offset + 28, 6].unpack("vvv")
      local = data[offset + 42, 4].unpack1("V")
      name = data[offset + 46, name_len].force_encoding("UTF-8")
      offset += 46 + name_len + extra_len + comment_len
      next if name.end_with?("/")
      raise ArgumentError, "cabeçalho local inválido" unless data[local, 4] == LOCAL

      lname, lextra = data[local + 26, 4].unpack("vv")
      raw = data[local + 30 + lname + lextra, csize]
      out[name] = case method
      when 0 then raw
      when 8 then Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(raw)
      else next
      end
    end
    out
  end
end
