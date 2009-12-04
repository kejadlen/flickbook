using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Net;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Xml;

namespace Flickbook
{
    /// <summary>
    /// Interaction logic for SetChooser.xaml
    /// </summary>
    public partial class SetChooser : Window
    {
        public SetChooser()
        {
            PhotoSets = new ObservableCollection<Flickr.PhotoSet>();

            InitializeComponent();

            // photosets = Flickr.request('photosets.getList', :user_id => flickr.nsid)['photosets']['photoset']
            var rsp = App.Flickr.Request("photosets.getList", new Dictionary<string, string> { { "user_id", App.Flickr.Nsid } });
            
            foreach(XmlNode setNode in rsp.SelectNodes("photosets/photoset"))
            {
                var photoSet = new Flickr.PhotoSet() {
                                    ID = setNode.Attributes.GetNamedItem("id").Value,
                                    Title = setNode.SelectSingleNode("title").InnerText,
                                    Description = setNode.SelectSingleNode("description").InnerText
                };

                PhotoSets.Add(photoSet);
            }

            importSet.IsEnabled = true;
        }

        public ObservableCollection<Flickr.PhotoSet> PhotoSets { get; set; }

        private void importSet_Click(object sender, RoutedEventArgs e)
        {
            importSet.IsEnabled = false;

            var photoSet = (Flickr.PhotoSet)photoSetsListView.SelectedItem;

            var description = new StringBuilder(photoSet.Description);

            if (description.Length > 0)
            {
                description.Append("\n\n");
            }

            description.AppendFormat("Original set available on Flickr: http://flickr.com/photos/{0}/sets/{0}/",
                                     App.Flickr.Nsid, photoSet.ID);

            // response = facebook.request('photos.createAlbum', :name => title, :description => description)
            var rsp = App.Facebook.Request("photos.createAlbum", new Dictionary<string, string> { { "name", photoSet.Title }, { "description", description.ToString() } });

            var album_id = rsp.SelectSingleNode("fb:aid", App.Facebook.NSMgr).InnerText;
            var album_link = rsp.SelectSingleNode("fb:link", App.Facebook.NSMgr).InnerText;

            // response = flickr.request('photosets.getPhotos', :photoset_id => photoset_id, :media => 'photos')
            rsp = App.Flickr.Request("photosets.getPhotos", new Dictionary<string, string> { { "photoset_id", photoSet.ID }, { "media", "photos" } });
            var photos = rsp.SelectNodes("photoset/photo");

            progressBar.Visibility = Visibility.Visible;
            progressBar.Maximum = photos.Count;
            progressBar.Value = 0;

            foreach (XmlNode photo in photos)
            {
                var photo_id = photo.Attributes.GetNamedItem("id").Value;
                var filename = String.Format("{0}_{1}.jpg", photo_id, photo.Attributes.GetNamedItem("secret").Value);

                rsp = App.Flickr.Request("photos.getInfo", new Dictionary<string, string>() { { "photo_id", photo_id } });
                var title = rsp.SelectSingleNode("photo/title").InnerText;
                description = new StringBuilder(rsp.SelectSingleNode("photo/description").InnerText);

                if (description.Length > 0)
                {
                    description.Append("\n\n");
                }

                description.AppendFormat("Higher-resolution photos available on Flickr: http://flickr.com/photos/{0}/{1}/",
                                         App.Flickr.Nsid, photo_id);

                var client = new WebClient();
                var stream = client.OpenRead(String.Format("http://farm{0}.static.flickr.com/{1}/{2}",
                                             photo.Attributes.GetNamedItem("farm").Value,
                                             photo.Attributes.GetNamedItem("server").Value,
                                             filename));

                progressBar.Value += 0.5;

                App.Facebook.UploadPhoto(filename, stream, new Dictionary<string, string>() { { "aid", album_id }, { "caption", description.ToString() } });

                progressBar.Value += 0.5;
            }
        }
    }
}
