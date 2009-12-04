using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Navigation;
using System.Windows.Shapes;

namespace Flickbook
{
    /// <summary>
    /// Interaction logic for Authorization.xaml
    /// </summary>
    public partial class Authorization : Window
    {
        public Authorization()
        {
            InitializeComponent();

            webBrowser.Navigate(App.Flickr.LoginUrl);
        }

        private void webBrowser_LoadCompleted(object sender, NavigationEventArgs e)
        {
            if (!App.Flickr.LoggedIn)
            {
                try
                {
                    App.Flickr.GetAuthToken();

                    webBrowser.Navigate(App.Facebook.LoginUrl);
                }
                catch (FlickrException)
                {
                }
            }
            else if (!App.Facebook.LoggedIn)
            {
                if (webBrowser.Source.AbsolutePath == "/connect/login_success.html")
                {
                    var json = Uri.UnescapeDataString(webBrowser.Source.Query);
                    App.Facebook.SessionKey = Regex.Match(json, @"""session_key"":""([^""]+)""").Groups[1].Value;
                    App.Facebook.SessionSecret = Regex.Match(json, @"""secret"":""([^""]+)""").Groups[1].Value;

                    // I should verify the UID in the URL is the same as the one returned by users.getLoggedInUser
                    // var xmlNode = facebook.Request("users.getLoggedInUser", new Dictionary<string, string>());

                    var setChooser = new SetChooser();
                    setChooser.Show();
                    this.Close();
                }
            }
        }
    }
}
