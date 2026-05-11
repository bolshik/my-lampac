using System.Globalization;

namespace Shared.Services.Utilities;

public static class StringConvert
{
    #region FindStartText
    public static string FindStartText(string data, string end)
    {
        if (data == null || end == null)
            return null;

        int endtIndex = data.IndexOf(end, StringComparison.Ordinal);
        if (endtIndex < 0)
            return null;

        return data.Substring(0, endtIndex);
    }
    #endregion

    #region FindLastText
    public static string FindLastText(string data, string start, string end = null)
    {
        if (data == null || start == null)
            return null;

        int startIndex = data.IndexOf(start, StringComparison.Ordinal);
        if (startIndex < 0)
            return null;

        if (end == null)
            return data.Substring(startIndex);

        int endIndex = data.IndexOf(end, startIndex, StringComparison.Ordinal);
        if (endIndex < 0)
            return null;

        return data.Substring(startIndex, endIndex - startIndex);
    }
    #endregion


    #region SearchName
    static readonly CultureInfo _cultureInfoSearchName = CultureInfo.GetCultureInfo("ru-RU");

    public static string SearchName(ReadOnlySpan<char> val, string empty = null)
    {
        if (val.IsEmpty)
            return empty;

        var sb = StringBuilderPool.ThreadInstance;

        for (int i = 0; i < val.Length; i++)
        {
            char c = val[i];

            // Быстро пропускаем whitespace и прочие явные разделители
            if (char.IsWhiteSpace(c))
                continue;

            // Оставляем только латиницу/кириллицу/цифры
            // (a-zA-Zа-яА-Я0-9Ёё)
            bool ok =
                (c >= '0' && c <= '9') ||
                (c >= 'A' && c <= 'Z') ||
                (c >= 'a' && c <= 'z') ||
                (c >= 'А' && c <= 'Я') ||
                (c >= 'а' && c <= 'я') ||
                c is 'Ё' or 'ё';

            if (!ok)
                continue;

            // - lower
            c = char.ToLower(c, _cultureInfoSearchName);

            // - ё -> е
            // - щ -> ш
            if (c == 'ё') c = 'е';
            else if (c == 'щ') c = 'ш';

            sb.Append(c);
        }

        if (sb.Length == 0)
            return empty;

        return sb.ToString();
    }
    #endregion
}
