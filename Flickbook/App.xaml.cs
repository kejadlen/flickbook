using System;
using System.Collections.Generic;
using System.Configuration;
using System.Data;
using System.Linq;
using System.Security.Cryptography;
using System.Windows;

namespace Flickbook
{
    /// <summary>
    /// Interaction logic for App.xaml
    /// </summary>
    public partial class App : Application
    {
        private static Flickr flickr = new Flickr();
        private static Facebook facebook = new Facebook();

        internal static Flickr Flickr
        {
            get { return flickr; }
        }

        internal static Facebook Facebook
        {
            get { return facebook; }
        }
    }
}
