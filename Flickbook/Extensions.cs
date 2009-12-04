using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;

namespace Extensions
{
    public static class Extensions
    {
        public static string Join<T>(this IEnumerable<T> strings, string seperator)
        {
            var en = strings.GetEnumerator();
            var sb = new StringBuilder();

            if (en.MoveNext())
            {
                sb.Append(en.Current);
            }

            while (en.MoveNext())
            {
                sb.Append(seperator).Append(en.Current);
            }

            return sb.ToString();
        }

        public static string Hexdigest(this MD5 md5, string input)
        {
            var data = md5.ComputeHash(Encoding.Default.GetBytes(input));

            var sb = new StringBuilder();

            for (int i = 0; i < data.Length; i++)
            {
                sb.Append(data[i].ToString("x2"));
            }

            return sb.ToString();
        }
    }
}
