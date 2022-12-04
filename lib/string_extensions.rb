module StringFunctions
  def integer? = (to_i.to_s == self)

  def substring_after_last(character)
    i = rindex(character)
    i ? self[i+1..-1] : self
  end

  def substring_before_first(character)
    i = index(character)
    i ? self[0..i-1] : self
  end

  def substring_before_last(character)
    i = rindex(character)
    i ? self[0..i-1] : self
  end
end
String.class_eval{include StringFunctions}

